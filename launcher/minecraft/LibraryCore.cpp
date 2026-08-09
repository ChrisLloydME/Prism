// SPDX-License-Identifier: GPL-3.0-only

#include "Library.h"

#include <QDir>
#include <QFileInfo>

#include <algorithm>

namespace {

QString removeInvalidPathChars(QString source, QChar replace)
{
    static const QString badCharacters = QStringLiteral("<>:\"|?*\r\n!");
    for (auto& character : source) {
        if (character.unicode() < 0x20 || !character.isPrint() || badCharacters.contains(character)) {
            character = replace;
        }
    }
    return source;
}

QString pathCombine(const QString& first, const QString& second)
{
    if (first.isEmpty()) {
        return second;
    }
    if (second.isEmpty()) {
        return first;
    }
    return QDir::cleanPath(first + QDir::separator() + second);
}

}  // namespace

void Library::getApplicableFiles(const RuntimeContext& runtimeContext,
                                 QStringList& jar,
                                 QStringList& native,
                                 QStringList& native32,
                                 QStringList& native64,
                                 const QString& overridePath) const
{
    const bool local = isLocal();
    const auto actualPath = [this, local, overridePath](QString relativePath) {
        relativePath = removeInvalidPathChars(std::move(relativePath), '-');
        QFileInfo output(pathCombine(storagePrefix(), relativePath));
        if (local && !overridePath.isEmpty()) {
            return QFileInfo(pathCombine(overridePath, output.fileName())).absoluteFilePath();
        }
        return output.absoluteFilePath();
    };

    const QString rawStorage = storageSuffix(runtimeContext);
    if (isNative()) {
        if (rawStorage.contains(QStringLiteral("${arch}"))) {
            auto storage32 = rawStorage;
            storage32.replace(QStringLiteral("${arch}"), QStringLiteral("32"));
            auto storage64 = rawStorage;
            storage64.replace(QStringLiteral("${arch}"), QStringLiteral("64"));
            native32 += actualPath(storage32);
            native64 += actualPath(storage64);
        } else {
            native += actualPath(rawStorage);
        }
    } else {
        jar += actualPath(rawStorage);
    }
}

bool Library::isActive(const RuntimeContext& runtimeContext) const
{
    Rule::Action ruleResult = Rule::Defer;
    if (!m_rules.empty()) {
        ruleResult = Rule::Disallow;
        for (auto rule : m_rules) {
            const auto current = rule.apply(runtimeContext);
            if (current != Rule::Defer) {
                ruleResult = current;
            }
        }
    }
    const bool active = m_rules.empty() || ruleResult == Rule::Allow;
    return active && (!isNative() || !getCompatibleNative(runtimeContext).isNull());
}

bool Library::isLocal() const
{
    return m_hint == QStringLiteral("local");
}

bool Library::isAlwaysStale() const
{
    return m_hint == QStringLiteral("always-stale");
}

QString Library::getCompatibleNative(const RuntimeContext& runtimeContext) const
{
    auto entry = m_nativeClassifiers.constFind(runtimeContext.getClassifier());
    if (entry == m_nativeClassifiers.constEnd() && runtimeContext.isLegacyArch()) {
        entry = m_nativeClassifiers.constFind(runtimeContext.system);
    }
    return entry == m_nativeClassifiers.constEnd() ? QString() : entry.value();
}

void Library::setStoragePrefix(QString prefix)
{
    m_storagePrefix = std::move(prefix);
}

QString Library::defaultStoragePrefix()
{
    return QStringLiteral("libraries/");
}

QString Library::storagePrefix() const
{
    return m_storagePrefix.isEmpty() ? defaultStoragePrefix() : m_storagePrefix;
}

QString Library::filename(const RuntimeContext& runtimeContext) const
{
    if (!m_filename.isEmpty()) {
        return m_filename;
    }
    if (!isNative()) {
        return m_name.getFileName();
    }
    auto nativeSpecifier = m_name;
    const auto nativeClassifier = getCompatibleNative(runtimeContext);
    nativeSpecifier.setClassifier(nativeClassifier.isNull() ? QStringLiteral("INVALID") : nativeClassifier);
    return nativeSpecifier.getFileName();
}

QString Library::displayName(const RuntimeContext& runtimeContext) const
{
    return m_displayname.isEmpty() ? filename(runtimeContext) : m_displayname;
}

QString Library::storageSuffix(const RuntimeContext& runtimeContext) const
{
    if (!isNative()) {
        return m_name.toPath(m_filename);
    }
    auto nativeSpecifier = m_name;
    const auto nativeClassifier = getCompatibleNative(runtimeContext);
    nativeSpecifier.setClassifier(nativeClassifier.isNull() ? QStringLiteral("INVALID") : nativeClassifier);
    return nativeSpecifier.toPath(m_filename);
}
