// SPDX-License-Identifier: GPL-3.0-only

#include <cstdlib>
#include <iostream>

#include "Application.h"

int main(int argc, char* argv[])
{
    // QApplication is temporarily retained because the extracted Prism domain
    // graph still contains QtGui/QtWidgets types. The --native-backend contract
    // prohibits creating presentation; disabling foreground transformation
    // prevents this helper from becoming a second Dock application. Subsequent
    // extraction can replace Application with QCoreApplication without
    // changing the native process boundary.
    qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("cocoa"));
    qputenv("QT_MAC_DISABLE_FOREGROUND_APPLICATION_TRANSFORM", QByteArrayLiteral("1"));

    Application app(argc, argv);
    switch (app.status()) {
        case Application::StartingUp:
        case Application::Initialized:
            Q_INIT_RESOURCE(multimc);
            Q_INIT_RESOURCE(backgrounds);
            Q_INIT_RESOURCE(documents);
            Q_INIT_RESOURCE(prismlauncher);
            Q_INIT_RESOURCE(pe_dark);
            Q_INIT_RESOURCE(pe_light);
            Q_INIT_RESOURCE(pe_blue);
            Q_INIT_RESOURCE(pe_colored);
            Q_INIT_RESOURCE(breeze_dark);
            Q_INIT_RESOURCE(breeze_light);
            Q_INIT_RESOURCE(OSX);
            Q_INIT_RESOURCE(iOS);
            Q_INIT_RESOURCE(flat);
            Q_INIT_RESOURCE(flat_white);
            Q_INIT_RESOURCE(shaders);
            return app.exec();
        case Application::Succeeded:
            return 0;
        case Application::Failed:
            return 1;
    }
    return 1;
}
