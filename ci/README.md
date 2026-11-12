# CI-Hilfsdateien

`debug.keystore` ist ein Signierschlüssel **nur für Test-Builds**. Das Passwort ist das übliche Android-Debug-Passwort (`android`) und kein Geheimnis. Der Schlüssel liegt im Repo, damit jede Test-APK gleich signiert ist und sich ohne Deinstallation über die vorige installieren lässt.

Der Schlüssel für die Veröffentlichung im Play Store ist ein anderer. Er kommt nie ins Repo.
