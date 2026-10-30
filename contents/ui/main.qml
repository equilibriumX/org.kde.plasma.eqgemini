/***************************************************************************
 *   Copyright 2026 by Barnak Zlatko <equilibrium@equilibriumos.com>             *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .        *
 ***************************************************************************/

import QtQuick
import QtWebEngine
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

PlasmoidItem {
    id: root

    width: Kirigami.Units.gridUnit * 30
    height: Kirigami.Units.gridUnit * 22

    // Ograničenja minimalne veličine (širina x visina)
    Layout.minimumWidth: 600
    Layout.minimumHeight: 650


    Plasmoid.backgroundHints: Plasma.StandardBackground

// 1. KOMPAKTNI PRIKAZ NA PANELU (Sređeno da nema preklapanja)
    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSize.small
        Layout.minimumHeight: Kirigami.Units.iconSize.small

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl(getIcon())
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    function getIcon() {
        if (Plasmoid.configuration.useCustomIcon && Plasmoid.configuration.customIconPath) {
            return "file://" + Plasmoid.configuration.customIconPath;
        }
        return "assets/gemini-kchat-icon.svg";
    }

    fullRepresentation: ColumnLayout {

        // Ograničenja minimalne veličine i za iskačući prozor (popup)
        Layout.minimumWidth: 600
        Layout.minimumHeight: 650


        anchors.fill: parent
        spacing: 0

        // 1. GLAVNI PROZOR (WebEngineView)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PlasmaComponents.Menu {
                id: linkContextMenu
                parent: webview

                property string link

                PlasmaComponents.MenuItem {
                    text: i18nc("@action:inmenu", "Open Link in Browser")
                    icon.name: "search-symbolic"
                    onClicked: Qt.openUrlExternally(linkContextMenu.link)
                }

                PlasmaComponents.MenuItem {
                    text: i18nc("@action:inmenu", "Copy Link Address")
                    icon.name: "edit-copy"
                    onClicked: webview.triggerWebAction(WebEngineView.CopyLinkToClipboard)
                }
            }

            WebEngineView {
                id: webview
                anchors.fill: parent
                clip: true
                zoomFactor: 1.0

                // Sprečavamo da Chromium uguši JS procese dok je u popup-u
                visible: true
                focus: Plasmoid.expanded

                settings.accelerated2dCanvasEnabled: true
                settings.webGLEnabled: true
                settings.localStorageEnabled: true
                settings.javascriptEnabled: true

                profile: WebEngineProfile {
                    storageName: "GeminiPWAProfile"
                    offTheRecord: false
                    httpCacheMaximumSize: 100 * 1024 * 1024
                }

                onUrlChanged: {
                    if (Plasmoid.configuration) {
                        Plasmoid.configuration.url = url;
                    }
                }

                Component.onCompleted: {
                    if (Plasmoid.configuration && Plasmoid.configuration.url) {
                        url = Plasmoid.configuration.url;
                    } else {
                        url = "https://gemini.google.com";
                    }
                }

                onLinkHovered: (hoveredUrl) => {
                    if (hoveredUrl.toString() !== "") {
                        mouseArea.cursorShape = Qt.PointingHandCursor;
                    } else {
                        mouseArea.cursorShape = Qt.ArrowCursor;
                    }
                }

                onLoadingChanged: (loadRequest) => {
                    if (loadRequest.status === 0) {
                        infoButton.dismiss();
                    }
                }

                onContextMenuRequested: (request) => {
                    if (request.linkUrl.toString() !== "") {
                        linkContextMenu.link = request.linkUrl;
                        linkContextMenu.open(request.x, request.y);
                        request.accepted = true;
                    }
                }

                onNewWindowRequested: (request) => {
                    var requestedUrl = request.requestedUrl;

                    if (request.userInitiated) {
                        Qt.openUrlExternally(requestedUrl);
                    } else {
                        infoButton.show(i18nc("An unwanted popup was blocked", "Popup blocked"), "document-close",
                                        i18n("Click here to open the following blocked popup:\n%1", requestedUrl), function () {
                            Qt.openUrlExternally(requestedUrl);
                            infoButton.dismiss();
                        });
                    }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                acceptedButtons: Qt.BackButton | Qt.ForwardButton
                onPressed: (mouse) => {
                    if (mouse.button === Qt.BackButton) {
                        webview.goBack();
                    } else if (mouse.button === Qt.ForwardButton) {
                        webview.goForward();
                    }
                }
            }
        }

        // 2. KONTROLE I "ASK GEMINI" POLJE NA DNU
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 2

            PlasmaComponents.Button {
                icon.name: "go-previous"
                onClicked: webview.goBack()
                enabled: webview.canGoBack
            }

            PlasmaComponents.Button {
                icon.name: "go-next"
                onClicked: webview.goForward()
                enabled: webview.canGoForward
            }

            PlasmaComponents.Button {
                icon.name: "go-home"
                onClicked: webview.url = "https://gemini.google.com"
            }

            PlasmaComponents.Button {
                icon.name: "list-add"
                onClicked: webview.url = "https://gemini.google.com/notebooks/splash?dest=create/"
            }

            PlasmaComponents.TextField {
                id: promptField
                Layout.fillWidth: true
                placeholderText: "Ask Gemini..."

                onAccepted: {
                    if (text.trim() !== "") {
                        var jsCode = `
                            (function() {
                                var input = document.querySelector('rich-textarea p, textarea, [contenteditable="true"]');
                                if (input) {
                                    input.focus();
                                    document.execCommand('insertText', false, "` + text.replace(/"/g, '\\"') + `");
                                    setTimeout(function() {
                                        var sendBtn = document.querySelector('button[aria-label*="Send"], button.send-button, button[mat-fab]');
                                        if (sendBtn) {
                                            sendBtn.click();
                                        }
                                    }, 200);
                                }
                            })();
                        `;
                        webview.runJavaScript(jsCode);
                        text = "";
                    }
                }

                onActiveFocusChanged: {
                    if (activeFocus) {
                        selectAll();
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: infoButton
                visible: false

                property var cb

                onClicked: cb()

                function show(buttonText, iconName, tooltipText, callback) {
                    infoButton.text = buttonText;
                    infoButton.icon.name = iconName;
                    infoButton.cb = callback;
                    infoButton.visible = true;
                }

                function dismiss() {
                    infoButton.visible = false;
                }
            }

            PlasmaComponents.Button {
                icon.name: webview.loading ? "process-stop" : "view-refresh"
                onClicked: webview.loading ? webview.stop() : webview.reload()
            }
        }
    }
}
