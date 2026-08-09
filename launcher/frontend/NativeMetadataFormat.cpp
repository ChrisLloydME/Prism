// SPDX-License-Identifier: GPL-3.0-only

#include "Json.h"
#include "meta/JsonFormat.h"

#include <QJsonArray>

using namespace Json;

namespace Meta {

MetadataVersion parseFormatVersion(const QJsonObject& object, bool required)
{
    if (!object.contains(QStringLiteral("formatVersion"))) {
        return required ? MetadataVersion::Invalid : MetadataVersion::InitialRelease;
    }
    const auto value = object.value(QStringLiteral("formatVersion"));
    if (!value.isDouble()) {
        return MetadataVersion::Invalid;
    }
    const int version = value.toInt();
    return version == 0 || version == 1 ? MetadataVersion::InitialRelease : MetadataVersion::Invalid;
}

void serializeFormatVersion(QJsonObject& object, MetadataVersion version)
{
    if (version != MetadataVersion::Invalid) {
        object.insert(QStringLiteral("formatVersion"), static_cast<int>(version));
    }
}

void parseRequires(const QJsonObject& object, RequireSet* output, const char* keyName)
{
    if (!object.contains(QLatin1String(keyName))) {
        return;
    }
    for (const auto& value : requireArray(object, keyName)) {
        const auto requirement = requireObject(value);
        output->insert({ requireString(requirement, "uid"),
                         requirement.value(QStringLiteral("equals")).toString(),
                         requirement.value(QStringLiteral("suggests")).toString() });
    }
}

void serializeRequires(QJsonObject& object, RequireSet* requirements, const char* keyName)
{
    if (!requirements || requirements->empty()) {
        return;
    }
    QJsonArray output;
    for (const auto& requirement : *requirements) {
        QJsonObject value;
        value.insert(QStringLiteral("uid"), requirement.uid);
        if (!requirement.equalsVersion.isEmpty()) {
            value.insert(QStringLiteral("equals"), requirement.equalsVersion);
        }
        if (!requirement.suggests.isEmpty()) {
            value.insert(QStringLiteral("suggests"), requirement.suggests);
        }
        output.append(value);
    }
    object.insert(QLatin1String(keyName), output);
}

MetadataVersion currentFormatVersion()
{
    return MetadataVersion::InitialRelease;
}

}  // namespace Meta
