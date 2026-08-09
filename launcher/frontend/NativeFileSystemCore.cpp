// SPDX-License-Identifier: GPL-3.0-only

#include "FileSystem.h"

#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

namespace FS {

QByteArray read(const QString& filename)
{
    QFile file(filename);
    if (!file.open(QFile::ReadOnly)) {
        throw FileSystemException("Unable to open " + filename + " for reading: " + file.errorString());
    }
    return file.readAll();
}

void write(const QString& filename, const QByteArray& data)
{
    const auto parent = QFileInfo(filename).dir();
    if (!parent.exists() && !QDir().mkpath(parent.absolutePath())) {
        throw FileSystemException("Unable to create the parent directory for " + filename);
    }
    QSaveFile file(filename);
    if (!file.open(QFile::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
        throw FileSystemException("Unable to write " + filename + ": " + file.errorString());
    }
}

}  // namespace FS
