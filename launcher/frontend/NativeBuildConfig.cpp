// SPDX-License-Identifier: GPL-3.0-only

#include "BuildConfig.h"

const Config BuildConfig;

Config::Config()
{
    LAUNCHER_NAME = QStringLiteral("Prism");
    LAUNCHER_DISPLAYNAME = QStringLiteral("Prism");
    LAUNCHER_APPID = QStringLiteral("com.lloydME.Prism");
    VERSION_MAJOR = 0;
    VERSION_MINOR = 0;
    VERSION_PATCH = 0;
    LIBRARY_BASE = QStringLiteral("https://libraries.minecraft.net/");
    VERSION_CHANNEL = QStringLiteral("stable");
    GIT_TAG = QStringLiteral("0.0.0");
}

QString Config::versionString() const
{
    return QStringLiteral("%1.%2.%3").arg(VERSION_MAJOR).arg(VERSION_MINOR).arg(VERSION_PATCH);
}

QString Config::printableVersionString() const
{
    return versionString();
}
