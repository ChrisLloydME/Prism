// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionLaunchRuntime.h"
#include "ProductionMinecraftLaunch.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSaveFile>
#include <QStringList>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <exception>
#include <regex>
#include <stdexcept>
#include <system_error>
#include <utility>

namespace {

constexpr std::size_t kMaxTaskLogEntries = kFrontendLogMaxEntries;
constexpr std::size_t kMaxTaskLogBytes = kFrontendLogMaxBytes;

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Production launch runtime requires an absolute data root");
    }
    return root;
}

bool isSafeIdentifier(const std::string& value)
{
    if (value.empty() || value.size() > 255 || value == "." || value == "..") {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character >= 0x20 && character != '/' && character != '\\' && character != 0x7f;
    });
}

bool isContained(const std::filesystem::path& root, const std::filesystem::path& candidate)
{
    const auto relative = candidate.lexically_normal().lexically_relative(root.lexically_normal());
    if (relative.empty() || relative.is_absolute() || relative.has_root_path()) {
        return false;
    }
    return std::none_of(relative.begin(), relative.end(), [](const auto& component) {
        return component == "..";
    });
}

std::string taskStateName(FrontendTaskState state)
{
    switch (state) {
        case FrontendTaskState::Queued:
            return "queued";
        case FrontendTaskState::Running:
            return "running";
        case FrontendTaskState::Cancelling:
            return "cancelling";
        case FrontendTaskState::Succeeded:
            return "succeeded";
        case FrontendTaskState::Failed:
            return "failed";
        case FrontendTaskState::Cancelled:
            return "cancelled";
    }
    return "failed";
}

std::optional<FrontendTaskState> taskStateFromName(const QString& value)
{
    const QString normalized = value.trimmed().toLower();
    if (normalized == QStringLiteral("queued")) {
        return FrontendTaskState::Queued;
    }
    if (normalized == QStringLiteral("running")) {
        return FrontendTaskState::Running;
    }
    if (normalized == QStringLiteral("cancelling")) {
        return FrontendTaskState::Cancelling;
    }
    if (normalized == QStringLiteral("succeeded")) {
        return FrontendTaskState::Succeeded;
    }
    if (normalized == QStringLiteral("failed")) {
        return FrontendTaskState::Failed;
    }
    if (normalized == QStringLiteral("cancelled")) {
        return FrontendTaskState::Cancelled;
    }
    return std::nullopt;
}

std::string progressKindName(FrontendTaskProgressKind kind)
{
    switch (kind) {
        case FrontendTaskProgressKind::None:
            return "none";
        case FrontendTaskProgressKind::Indeterminate:
            return "indeterminate";
        case FrontendTaskProgressKind::Determinate:
            return "determinate";
    }
    return "none";
}

std::optional<FrontendTaskProgressKind> progressKindFromName(const QString& value)
{
    const QString normalized = value.trimmed().toLower();
    if (normalized == QStringLiteral("none")) {
        return FrontendTaskProgressKind::None;
    }
    if (normalized == QStringLiteral("indeterminate")) {
        return FrontendTaskProgressKind::Indeterminate;
    }
    if (normalized == QStringLiteral("determinate")) {
        return FrontendTaskProgressKind::Determinate;
    }
    return std::nullopt;
}

std::string terminalOutcomeName(FrontendTaskTerminalOutcome outcome)
{
    switch (outcome) {
        case FrontendTaskTerminalOutcome::Succeeded:
            return "succeeded";
        case FrontendTaskTerminalOutcome::Failed:
            return "failed";
        case FrontendTaskTerminalOutcome::Cancelled:
            return "cancelled";
    }
    return "failed";
}

std::optional<FrontendTaskTerminalOutcome> terminalOutcomeFromName(const QString& value)
{
    const QString normalized = value.trimmed().toLower();
    if (normalized == QStringLiteral("succeeded")) {
        return FrontendTaskTerminalOutcome::Succeeded;
    }
    if (normalized == QStringLiteral("failed")) {
        return FrontendTaskTerminalOutcome::Failed;
    }
    if (normalized == QStringLiteral("cancelled")) {
        return FrontendTaskTerminalOutcome::Cancelled;
    }
    return std::nullopt;
}

bool isTerminal(FrontendTaskState state)
{
    return state == FrontendTaskState::Succeeded || state == FrontendTaskState::Failed
        || state == FrontendTaskState::Cancelled;
}

QJsonObject terminalToJson(const FrontendTaskTerminalResult& result)
{
    QJsonObject object;
    object.insert("outcome", QString::fromStdString(terminalOutcomeName(result.outcome)));
    object.insert("localizationKey", QString::fromStdString(result.localizationKey));
    object.insert("diagnosticText", QString::fromStdString(result.diagnosticText));
    object.insert("partialChangesRolledBack", result.partialChangesRolledBack);
    QJsonObject substitutions;
    for (const auto& [key, value] : result.substitutionValues) {
        substitutions.insert(QString::fromStdString(key), QString::fromStdString(value));
    }
    object.insert("substitutionValues", substitutions);
    return object;
}

std::optional<FrontendTaskTerminalResult> terminalFromJson(const QJsonObject& object)
{
    const auto outcome = terminalOutcomeFromName(object.value("outcome").toString());
    const QString localizationKey = object.value("localizationKey").toString().trimmed();
    if (!outcome || localizationKey.isEmpty()) {
        return std::nullopt;
    }

    FrontendTaskTerminalResult result;
    result.outcome = *outcome;
    result.localizationKey = localizationKey.toStdString();
    result.diagnosticText = object.value("diagnosticText").toString().toStdString();
    result.partialChangesRolledBack = object.value("partialChangesRolledBack").toBool(false);
    const QJsonObject substitutions = object.value("substitutionValues").toObject();
    for (auto iterator = substitutions.constBegin(); iterator != substitutions.constEnd(); ++iterator) {
        result.substitutionValues.emplace_back(iterator.key().toStdString(), iterator.value().toString().toStdString());
    }
    return result;
}

QJsonObject snapshotToJson(const FrontendTaskSnapshot& snapshot)
{
    QJsonObject object;
    object.insert("id", QString::fromStdString(snapshot.id));
    object.insert("title", QString::fromStdString(snapshot.title));
    object.insert("state", QString::fromStdString(taskStateName(snapshot.state)));
    object.insert("progressKind", QString::fromStdString(progressKindName(snapshot.progressKind)));
    object.insert("progressFraction", snapshot.progressFraction);
    object.insert("cancellationAllowed", snapshot.cancellationAllowed);
    if (snapshot.terminalResult.has_value()) {
        object.insert("terminalResult", terminalToJson(*snapshot.terminalResult));
    }
    return object;
}

std::optional<FrontendTaskSnapshot> snapshotFromJson(const QJsonObject& object)
{
    const QString id = object.value("id").toString().trimmed();
    const QString title = object.value("title").toString();
    const auto state = taskStateFromName(object.value("state").toString());
    const auto progressKind = progressKindFromName(object.value("progressKind").toString());
    if (id.isEmpty() || !state || !progressKind) {
        return std::nullopt;
    }

    FrontendTaskSnapshot snapshot;
    snapshot.id = id.toStdString();
    snapshot.title = title.toStdString();
    snapshot.state = *state;
    snapshot.progressKind = *progressKind;
    snapshot.progressFraction = object.value("progressFraction").toDouble(0.0);
    snapshot.cancellationAllowed = object.value("cancellationAllowed").toBool(false);
    if (object.value("terminalResult").isObject()) {
        snapshot.terminalResult = terminalFromJson(object.value("terminalResult").toObject());
        if (!snapshot.terminalResult.has_value()) {
            return std::nullopt;
        }
    }
    return snapshot;
}

std::string redactText(std::string text, const std::vector<std::string>& secrets)
{
    for (const std::string& secret : secrets) {
        if (secret.size() < 3) {
            continue;
        }
        std::size_t offset = 0;
        while ((offset = text.find(secret, offset)) != std::string::npos) {
            text.replace(offset, secret.size(), "<redacted>");
            offset += sizeof("<redacted>") - 1;
        }
    }

    const std::regex credentialPattern(
        R"(((--)?(access[_-]?token|refresh[_-]?token|client[_-]?secret|password|authorization|username|email|account|uuid|token)\s*([:=]|\s)\s*(Bearer\s+)?)([^\s,;]+))",
        std::regex_constants::icase);
    return std::regex_replace(text, credentialPattern, "$1<redacted>");
}

ProductionLaunchRuntime::ProcessResult defaultProcessExecutor(
    const ProductionLaunchRuntime::ProcessSpec& spec,
    const ProductionLaunchRuntime::ProcessLogHandler& log,
    const ProductionLaunchRuntime::CancellationCheck& cancelled)
{
    QProcess process;
    process.setProgram(QString::fromStdString(spec.program));
    QStringList arguments;
    for (const auto& argument : spec.arguments) {
        arguments.append(QString::fromStdString(argument));
    }
    process.setArguments(arguments);

    QProcessEnvironment environment;
    for (const auto& [key, value] : spec.environment) {
        environment.insert(QString::fromStdString(key), QString::fromStdString(value));
    }
    process.setProcessEnvironment(environment);
    process.setWorkingDirectory(QString::fromStdString(spec.workingDirectory.string()));
    process.setProcessChannelMode(QProcess::SeparateChannels);
    process.start();
    if (!process.waitForStarted(3000)) {
        return { ProductionLaunchRuntime::ProcessResult::Outcome::Failed, -1,
            process.errorString().toStdString() };
    }
    if (!spec.standardInput.empty()) {
        process.write(QByteArray::fromStdString(spec.standardInput));
    }
    if (!spec.launchInput.empty()) {
        process.write(QByteArray::fromStdString(spec.launchInput));
    }

    bool cancellationRequested = false;
    while (process.state() != QProcess::NotRunning) {
        if (cancelled && cancelled()) {
            cancellationRequested = true;
            process.kill();
        }
        if (process.waitForReadyRead(50)) {
            const QByteArray standardOutput = process.readAllStandardOutput();
            const QByteArray standardError = process.readAllStandardError();
            if (log && !standardOutput.isEmpty()) {
                log(standardOutput.toStdString());
            }
            if (log && !standardError.isEmpty()) {
                log(standardError.toStdString());
            }
        }
    }
    const QByteArray remainingOutput = process.readAllStandardOutput();
    const QByteArray remainingError = process.readAllStandardError();
    if (log && !remainingOutput.isEmpty()) {
        log(remainingOutput.toStdString());
    }
    if (log && !remainingError.isEmpty()) {
        log(remainingError.toStdString());
    }

    if (cancellationRequested || (cancelled && cancelled())) {
        return { ProductionLaunchRuntime::ProcessResult::Outcome::Cancelled, process.exitCode(), {} };
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        return { ProductionLaunchRuntime::ProcessResult::Outcome::Failed, process.exitCode(),
            process.errorString().toStdString() };
    }
    return { ProductionLaunchRuntime::ProcessResult::Outcome::Succeeded, process.exitCode(), {} };
}

}  // namespace

struct ProductionLaunchRuntime::TaskRecord final {
    std::string instanceIdentifier;
    std::filesystem::path instancePath;
    mutable std::mutex mutex;
    FrontendTaskSnapshot snapshot;
    std::deque<FrontendLogEntry> entries;
    std::uint64_t droppedEntryCount = 0;
    std::uint64_t totalByteCount = 0;
    std::uint64_t nextSequence = 0;
    std::vector<std::string> secrets;
    std::atomic_bool cancelRequested = false;
    std::thread worker;
};

ProductionLaunchRuntime::ProductionLaunchRuntime(
    std::filesystem::path dataRoot,
    ProcessExecutor executor,
    LaunchSessionProvider sessionProvider,
    std::filesystem::path backendExecutable)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))),
      m_instancesRoot(m_dataRoot / "instances"),
      m_tasksRoot(m_dataRoot / "tasks"),
      m_executor(executor ? std::move(executor) : defaultProcessExecutor),
      m_sessionProvider(std::move(sessionProvider)),
      m_backendExecutable(std::move(backendExecutable).lexically_normal())
{
    std::error_code error;
    if (std::filesystem::exists(m_dataRoot, error)
        && (error || std::filesystem::is_symlink(m_dataRoot, error))) {
        throw std::invalid_argument("Production launch runtime rejects a symlinked data root");
    }
    std::filesystem::create_directories(m_tasksRoot, error);
    if (error || std::filesystem::is_symlink(m_tasksRoot, error)
        || !std::filesystem::is_directory(m_tasksRoot, error) || error) {
        throw std::runtime_error("Production launch runtime could not create its task root");
    }
    loadPersistedRecords();
}

ProductionLaunchRuntime::~ProductionLaunchRuntime() noexcept
{
    shutdown();
}

std::string ProductionLaunchRuntime::taskIdentifierForInstance(const std::string& instanceIdentifier)
{
    return "launch." + instanceIdentifier;
}

std::shared_ptr<ProductionLaunchRuntime::TaskRecord> ProductionLaunchRuntime::makeTaskRecord(
    const std::string& instanceIdentifier)
{
    auto record = std::make_shared<TaskRecord>();
    record->instanceIdentifier = instanceIdentifier;
    record->instancePath = m_instancesRoot / instanceIdentifier;
    record->snapshot.id = taskIdentifierForInstance(instanceIdentifier);
    record->snapshot.title = "Launch " + instanceIdentifier;
    record->snapshot.state = FrontendTaskState::Queued;
    record->snapshot.progressKind = FrontendTaskProgressKind::Indeterminate;
    record->snapshot.progressFraction = 0.0;
    record->snapshot.cancellationAllowed = true;
    return record;
}

std::optional<ProductionLaunchRuntime::ProcessSpec> ProductionLaunchRuntime::readProcessSpec(
    const std::string& instanceIdentifier,
    const std::shared_ptr<TaskRecord>& record,
    std::string& diagnostic) const
{
    if (!isSafeIdentifier(instanceIdentifier)) {
        diagnostic = "Instance identifier is invalid";
        return std::nullopt;
    }

    const auto instancePath = m_instancesRoot / instanceIdentifier;
    std::error_code error;
    if (!std::filesystem::is_directory(instancePath, error) || error
        || std::filesystem::is_symlink(instancePath, error) || error) {
        diagnostic = "A Native Prism instance is not available";
        return std::nullopt;
    }
    if (!isContained(m_dataRoot, instancePath)) {
        diagnostic = "The Native Prism instance is outside its data root";
        return std::nullopt;
    }
    if (!m_sessionProvider) {
        diagnostic = "The Native Prism launch identity provider is unavailable";
        return std::nullopt;
    }
    const auto session = m_sessionProvider(instanceIdentifier);
    if (!session.has_value()) {
        diagnostic = "A usable launch identity is unavailable";
        return std::nullopt;
    }
    if (!m_backendExecutable.empty() && m_backendExecutable.is_absolute()
        && std::filesystem::is_regular_file(m_backendExecutable, error) && !error
        && !std::filesystem::is_symlink(m_backendExecutable, error) && !error) {
        ProcessSpec process;
        process.program = m_backendExecutable.string();
        process.arguments = {
            "--native-backend",
            "--dir",
            m_dataRoot.string(),
            "--launch",
            instanceIdentifier,
        };
        if (session->mode == ProductionLaunchMode::Offline) {
            process.arguments.push_back("--offline");
            process.arguments.push_back(session->playerName);
        } else if (!session->playerName.empty()) {
            process.arguments.push_back("--profile");
            process.arguments.push_back(session->playerName);
        }
        process.environment["QT_QPA_PLATFORM"] = "cocoa";
        process.environment["QT_MAC_DISABLE_FOREGROUND_APPLICATION_TRANSFORM"] = "1";
        process.environment["NO_COLOR"] = "1";
        process.workingDirectory = m_dataRoot;
        record->secrets = session->secrets;
        return process;
    }
    auto build = buildProductionMinecraftLaunch(m_dataRoot, instancePath, instanceIdentifier, *session);
    if (!build.process.has_value()) {
        diagnostic = std::move(build.diagnostic);
        return std::nullopt;
    }
    record->secrets = std::move(build.secrets);
    return std::move(*build.process);
}

void ProductionLaunchRuntime::appendLog(const std::shared_ptr<TaskRecord>& record, std::string text, bool truncated)
{
    text = redactText(std::move(text), record->secrets);
    {
        std::lock_guard<std::mutex> lock(record->mutex);
        FrontendLogEntry entry;
        entry.sequence = record->nextSequence++;
        entry.text = std::move(text);
        entry.truncated = truncated;
        if (entry.text.size() > kMaxTaskLogBytes) {
            entry.text.resize(kMaxTaskLogBytes);
            entry.truncated = true;
        }
        record->totalByteCount += entry.text.size();
        record->entries.push_back(std::move(entry));
        while (record->entries.size() > kMaxTaskLogEntries || record->totalByteCount > kMaxTaskLogBytes) {
            record->totalByteCount -= record->entries.front().text.size();
            record->entries.pop_front();
            ++record->droppedEntryCount;
        }
    }
    persistRecord(record);
}

void ProductionLaunchRuntime::persistRecord(const std::shared_ptr<TaskRecord>& record) const
{
    FrontendTaskSnapshot snapshot;
    std::deque<FrontendLogEntry> entries;
    std::uint64_t droppedEntryCount = 0;
    std::uint64_t totalByteCount = 0;
    {
        std::lock_guard<std::mutex> lock(record->mutex);
        snapshot = record->snapshot;
        entries = record->entries;
        droppedEntryCount = record->droppedEntryCount;
        totalByteCount = record->totalByteCount;
    }

    QJsonObject root = snapshotToJson(snapshot);
    root.insert("droppedEntryCount", static_cast<qint64>(droppedEntryCount));
    root.insert("totalByteCount", static_cast<qint64>(totalByteCount));
    QJsonArray log;
    for (const FrontendLogEntry& entry : entries) {
        QJsonObject item;
        item.insert("sequence", static_cast<qint64>(entry.sequence));
        item.insert("text", QString::fromStdString(entry.text));
        item.insert("truncated", entry.truncated);
        log.append(item);
    }
    root.insert("log", log);

    QSaveFile file(QString::fromStdString((m_tasksRoot / (snapshot.id + ".json")).string()));
    if (!file.open(QIODevice::WriteOnly)) {
        return;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    file.commit();
}

void ProductionLaunchRuntime::notifyTask(const std::shared_ptr<TaskRecord>& record)
{
    persistRecord(record);
    FrontendTaskSnapshot snapshot;
    FrontendRuntimeDependencies::TaskObservationHandler observer;
    {
        std::lock_guard<std::mutex> lock(record->mutex);
        snapshot = record->snapshot;
    }
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        observer = m_taskObserver;
    }
    if (observer) {
        observer(snapshot);
    }
}

void ProductionLaunchRuntime::runTask(const std::shared_ptr<TaskRecord>& record, ProcessSpec spec)
{
    {
        std::lock_guard<std::mutex> lock(record->mutex);
        record->snapshot.state = FrontendTaskState::Running;
        record->snapshot.cancellationAllowed = true;
    }
    appendLog(record, "Preparing launch process");
    notifyTask(record);

    ProcessResult result;
    try {
        result = m_executor(
            spec,
            [this, record](std::string text) { appendLog(record, std::move(text)); },
            [record] { return record->cancelRequested.load(); });
    } catch (const std::exception& exception) {
        result.outcome = ProcessResult::Outcome::Failed;
        result.diagnostic = exception.what();
    } catch (...) {
        result.outcome = ProcessResult::Outcome::Failed;
        result.diagnostic = "Launch process executor failed";
    }

    FrontendTaskTerminalResult terminal;
    {
        std::lock_guard<std::mutex> lock(record->mutex);
        if (record->cancelRequested.load() || result.outcome == ProcessResult::Outcome::Cancelled) {
            record->snapshot.state = FrontendTaskState::Cancelled;
            terminal.outcome = FrontendTaskTerminalOutcome::Cancelled;
            terminal.localizationKey = "launch.cancelled";
            terminal.diagnosticText = "Launch was cancelled.";
        } else if (result.outcome == ProcessResult::Outcome::Succeeded && result.exitCode == 0) {
            record->snapshot.state = FrontendTaskState::Succeeded;
            terminal.outcome = FrontendTaskTerminalOutcome::Succeeded;
            terminal.localizationKey = "launch.succeeded";
            terminal.diagnosticText = "Launch process exited successfully.";
        } else {
            record->snapshot.state = FrontendTaskState::Failed;
            terminal.outcome = FrontendTaskTerminalOutcome::Failed;
            terminal.localizationKey = "launch.process.failed";
            terminal.diagnosticText = redactText(
                result.diagnostic.empty() ? "Launch process failed." : result.diagnostic,
                record->secrets);
        }
        record->snapshot.cancellationAllowed = false;
        record->snapshot.progressKind = FrontendTaskProgressKind::None;
        record->snapshot.progressFraction = 0.0;
        record->snapshot.terminalResult = terminal;
    }
    appendLog(record, terminal.diagnosticText);
    notifyTask(record);
}

FrontendInstanceCommandResult ProductionLaunchRuntime::launchInstance(const std::string& instanceIdentifier)
{
    if (!isSafeIdentifier(instanceIdentifier)) {
        return FrontendInstanceCommandResult::Rejected;
    }

    std::shared_ptr<TaskRecord> oldRecord;
    std::thread oldWorker;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        if (m_shutdown) {
            return FrontendInstanceCommandResult::Rejected;
        }
        const auto iterator = m_records.find(taskIdentifierForInstance(instanceIdentifier));
        if (iterator != m_records.end()) {
            oldRecord = iterator->second;
            std::lock_guard<std::mutex> recordLock(oldRecord->mutex);
            if (!isTerminal(oldRecord->snapshot.state)) {
                return FrontendInstanceCommandResult::Rejected;
            }
            if (oldRecord->worker.joinable()) {
                oldWorker = std::move(oldRecord->worker);
            }
        }
    }
    if (oldWorker.joinable()) {
        oldWorker.join();
    }

    auto record = makeTaskRecord(instanceIdentifier);
    std::string diagnostic;
    const auto spec = readProcessSpec(instanceIdentifier, record, diagnostic);
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        if (m_shutdown) {
            return FrontendInstanceCommandResult::Rejected;
        }
        m_records[record->snapshot.id] = record;
        if (spec.has_value()) {
            record->worker = std::thread([this, record, spec = *spec] { runTask(record, spec); });
        }
    }

    if (!spec.has_value()) {
        notifyTask(record);
        FrontendTaskTerminalResult terminal;
        terminal.outcome = FrontendTaskTerminalOutcome::Failed;
        terminal.localizationKey = "launch.preparation.failed";
        terminal.diagnosticText = diagnostic;
        {
            std::lock_guard<std::mutex> lock(record->mutex);
            record->snapshot.state = FrontendTaskState::Failed;
            record->snapshot.cancellationAllowed = false;
            record->snapshot.progressKind = FrontendTaskProgressKind::None;
            record->snapshot.terminalResult = terminal;
        }
        appendLog(record, diagnostic);
        notifyTask(record);
        return FrontendInstanceCommandResult::Succeeded;
    }

    return FrontendInstanceCommandResult::Succeeded;
}

FrontendInstanceCommandResult ProductionLaunchRuntime::stopInstance(const std::string& instanceIdentifier)
{
    if (!isSafeIdentifier(instanceIdentifier)) {
        return FrontendInstanceCommandResult::Rejected;
    }
    const auto taskIdentifier = taskIdentifierForInstance(instanceIdentifier);
    std::shared_ptr<TaskRecord> record;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        const auto iterator = m_records.find(taskIdentifier);
        if (iterator == m_records.end()) {
            return FrontendInstanceCommandResult::UnknownInstance;
        }
        record = iterator->second;
    }

    {
        std::lock_guard<std::mutex> lock(record->mutex);
        if (isTerminal(record->snapshot.state)) {
            return FrontendInstanceCommandResult::Rejected;
        }
        record->cancelRequested.store(true);
        record->snapshot.state = FrontendTaskState::Cancelling;
        record->snapshot.cancellationAllowed = false;
    }
    notifyTask(record);
    return FrontendInstanceCommandResult::Succeeded;
}

std::optional<FrontendTaskSnapshot> ProductionLaunchRuntime::taskSnapshot(const std::string& taskIdentifier) const
{
    std::shared_ptr<TaskRecord> record;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        const auto iterator = m_records.find(taskIdentifier);
        if (iterator == m_records.end()) {
            return std::nullopt;
        }
        record = iterator->second;
    }
    std::lock_guard<std::mutex> lock(record->mutex);
    return record->snapshot;
}

FrontendTaskCancellationResult ProductionLaunchRuntime::cancelTask(const std::string& taskIdentifier)
{
    std::shared_ptr<TaskRecord> record;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        const auto iterator = m_records.find(taskIdentifier);
        if (iterator == m_records.end()) {
            return FrontendTaskCancellationResult::UnknownTask;
        }
        record = iterator->second;
    }

    {
        std::lock_guard<std::mutex> lock(record->mutex);
        if (isTerminal(record->snapshot.state)) {
            return FrontendTaskCancellationResult::AlreadyTerminal;
        }
        record->cancelRequested.store(true);
        record->snapshot.state = FrontendTaskState::Cancelling;
        record->snapshot.cancellationAllowed = false;
    }
    notifyTask(record);
    return FrontendTaskCancellationResult::Requested;
}

bool ProductionLaunchRuntime::streamTaskLogs(
    const std::string& taskIdentifier, const FrontendRuntimeDependencies::LogEntryHandler& handler) const
{
    if (!handler) {
        return false;
    }
    std::shared_ptr<TaskRecord> record;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        const auto iterator = m_records.find(taskIdentifier);
        if (iterator == m_records.end()) {
            return false;
        }
        record = iterator->second;
    }
    std::deque<FrontendLogEntry> entries;
    {
        std::lock_guard<std::mutex> lock(record->mutex);
        entries = record->entries;
    }
    for (const FrontendLogEntry& entry : entries) {
        handler(entry);
    }
    return true;
}

bool ProductionLaunchRuntime::startTaskObservation(FrontendRuntimeDependencies::TaskObservationHandler handler)
{
    if (!handler) {
        return false;
    }
    std::vector<FrontendTaskSnapshot> snapshots;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        if (m_shutdown || m_taskObserver) {
            return false;
        }
        m_taskObserver = handler;
        for (const auto& [identifier, record] : m_records) {
            static_cast<void>(identifier);
            std::lock_guard<std::mutex> recordLock(record->mutex);
            snapshots.push_back(record->snapshot);
        }
    }
    for (const auto& snapshot : snapshots) {
        handler(snapshot);
    }
    return true;
}

void ProductionLaunchRuntime::stopTaskObservation() noexcept
{
    std::lock_guard<std::mutex> lock(m_runtimeMutex);
    m_taskObserver = {};
}

void ProductionLaunchRuntime::cancelPendingWork() noexcept
{
    std::vector<std::shared_ptr<TaskRecord>> records;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        for (const auto& [identifier, record] : m_records) {
            static_cast<void>(identifier);
            records.push_back(record);
        }
    }
    for (const auto& record : records) {
        record->cancelRequested.store(true);
    }
}

void ProductionLaunchRuntime::shutdown() noexcept
{
    std::vector<std::shared_ptr<TaskRecord>> records;
    {
        std::lock_guard<std::mutex> lock(m_runtimeMutex);
        if (m_shutdown) {
            return;
        }
        m_shutdown = true;
        m_taskObserver = {};
        for (const auto& [identifier, record] : m_records) {
            static_cast<void>(identifier);
            record->cancelRequested.store(true);
            records.push_back(record);
        }
    }
    for (const auto& record : records) {
        if (record->worker.joinable() && record->worker.get_id() != std::this_thread::get_id()) {
            record->worker.join();
        }
    }
}

void ProductionLaunchRuntime::loadPersistedRecords()
{
    QDir directory(QString::fromStdString(m_tasksRoot.string()));
    const QStringList files = directory.entryList({ QStringLiteral("launch.*.json") }, QDir::Files, QDir::Name);
    for (const QString& fileName : files) {
        QFile file(directory.filePath(fileName));
        if (!file.open(QIODevice::ReadOnly)) {
            continue;
        }
        QJsonParseError error{};
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            continue;
        }
        const auto snapshot = snapshotFromJson(document.object());
        if (!snapshot.has_value() || !snapshot->id.starts_with("launch.")) {
            continue;
        }
        auto record = makeTaskRecord(snapshot->id.substr(sizeof("launch.") - 1));
        record->snapshot = *snapshot;
        const QJsonArray log = document.object().value("log").toArray();
        for (const QJsonValue& value : log) {
            const QJsonObject object = value.toObject();
            FrontendLogEntry entry;
            entry.sequence = static_cast<std::uint64_t>(object.value("sequence").toInteger());
            entry.text = object.value("text").toString().toStdString();
            entry.truncated = object.value("truncated").toBool(false);
            record->entries.push_back(std::move(entry));
            record->nextSequence = std::max(record->nextSequence, record->entries.back().sequence + 1);
        }
        record->droppedEntryCount = static_cast<std::uint64_t>(document.object().value("droppedEntryCount").toInteger());
        record->totalByteCount = static_cast<std::uint64_t>(document.object().value("totalByteCount").toInteger());
        if (!isTerminal(record->snapshot.state)) {
            record->snapshot.state = FrontendTaskState::Cancelled;
            record->snapshot.progressKind = FrontendTaskProgressKind::None;
            record->snapshot.progressFraction = 0.0;
            record->snapshot.cancellationAllowed = false;
            record->snapshot.terminalResult = FrontendTaskTerminalResult{
                FrontendTaskTerminalOutcome::Cancelled,
                "launch.reconstructed.cancelled",
                {},
                "Launch was cancelled while Native Prism was not running.",
                false,
            };
            appendLog(record, "Recovered an unfinished launch as cancelled");
            persistRecord(record);
        }
        m_records.emplace(record->snapshot.id, std::move(record));
    }
}

std::shared_ptr<ProductionLaunchRuntime> makeProductionLaunchRuntime(
    std::filesystem::path dataRoot,
    ProductionLaunchRuntime::ProcessExecutor executor,
    ProductionLaunchRuntime::LaunchSessionProvider sessionProvider,
    std::filesystem::path backendExecutable)
{
    return std::make_shared<ProductionLaunchRuntime>(
        std::move(dataRoot), std::move(executor), std::move(sessionProvider), std::move(backendExecutable));
}

FrontendRuntimeDependencies productionLaunchRuntimeDependencies(
    std::shared_ptr<ProductionLaunchRuntime> runtime, FrontendRuntimeDependencies dependencies)
{
    if (!runtime) {
        throw std::invalid_argument("Production launch dependencies require a runtime");
    }
    dependencies.launchInstance = [runtime](const std::filesystem::path&, const std::string& identifier) {
        return runtime->launchInstance(identifier);
    };
    dependencies.stopInstance = [runtime](const std::filesystem::path&, const std::string& identifier) {
        return runtime->stopInstance(identifier);
    };
    dependencies.loadTaskSnapshot = [runtime](const std::filesystem::path&, const std::string& identifier) {
        return runtime->taskSnapshot(identifier);
    };
    dependencies.cancelTask = [runtime](const std::filesystem::path&, const std::string& identifier) {
        return runtime->cancelTask(identifier);
    };
    dependencies.streamTaskLogs = [runtime](
                                      const std::filesystem::path&,
                                      const std::string& identifier,
                                      const FrontendRuntimeDependencies::LogEntryHandler& handler) {
        return runtime->streamTaskLogs(identifier, handler);
    };
    dependencies.startTaskObservation = [runtime](FrontendRuntimeDependencies::TaskObservationHandler handler) {
        return runtime->startTaskObservation(std::move(handler));
    };
    dependencies.stopTaskObservation = [runtime] { runtime->stopTaskObservation(); };
    return dependencies;
}
