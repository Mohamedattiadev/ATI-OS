// qsipc -- minimal drop-in replacement for `qs -p <config-path> ipc call
// <target> <function> [args...]`.
//
// Links only Qt6Core + Qt6Network, not Qt6Quick/Qt6Qml/wayland-client --
// unlike /usr/bin/qs, which is a symlink to the full `quickshell` binary
// (94 linked libs via ldd) and pays for the whole QML/Quick/Wayland stack
// just to make one IPC call. Measured: 37-45ms typical for `qs ipc call`
// (confirmed pure process-startup cost, not the IPC round trip -- `qs
// --version` costs the same), 14-22ms for this. Protocol and instance
// registry both read from quickshell's own source (outfoxxed/quickshell,
// read 2026-08-20):
//
//   - src/ipc/ipc.cpp + src/io/ipccomm.cpp: IpcCommand is a std::variant
//     tagged by a leading quint8, StringCallCommand is index 3, fields
//     (QString target, QString function, QVector<QString> arguments).
//     StringCallResponse is tagged the same way, Completed at index 5
//     (bool isVoid, QString returnValue).
//   - $XDG_RUNTIME_DIR/quickshell/by-id/<id>/instance.lock: starts with
//     two QDataStream QStrings, (instance id, the exact config path the
//     instance was launched with -- NOT symlink-resolved, confirmed by
//     hexdump: a `-p .../tide-island-fork/treetab.qml` instance stores
//     that literal string, not its .dotfiles/ target). Only those first
//     two fields are read here; the rest of the file (a hash, a bus name,
//     a Wayland display) is not needed for resolution and its exact
//     layout was not reverse-engineered further than that.
//
// `qs -p <path>` accepts either a shell.qml file or its containing
// directory; matched here the same way -- append /shell.qml unless the
// given path already ends in .qml.
#include <QCoreApplication>
#include <QDataStream>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocalSocket>
#include <QTextStream>
#include <algorithm>
#include <cstdio>
#include <cstring>

// Returns every by-id directory whose instance.lock names this config path,
// newest instance.lock mtime first. NOT deduplicated to one answer here: a
// dead instance's by-id directory can outlive the process that made it (see
// AtiScriptsV1/bar-action's own note on this -- 38 stale ids measured piled
// up under ~/.cache/quickshell once), and this machine had exactly that for
// popups.qml while this file was being tested: two entries, one live. Trying
// the newest first and falling through on a failed connect (in main(), not
// here) is what makes that self-healing instead of a coin flip.
static QStringList resolveSocketCandidates(const QString& configPathArg) {
    QFileInfo info(configPathArg);
    QString wantPath = info.absoluteFilePath();
    if (!wantPath.endsWith(".qml")) wantPath += "/shell.qml";

    QString runtimeDir = qEnvironmentVariable("XDG_RUNTIME_DIR", "/tmp");
    QDir byId(runtimeDir + "/quickshell/by-id");
    const auto entries = byId.entryList(QDir::Dirs | QDir::NoDotAndDotDot);

    QList<QPair<QDateTime, QString>> matches;
    for (const auto& id : entries) {
        QString lockPath = byId.filePath(id) + "/instance.lock";
        QFile lock(lockPath);
        if (!lock.open(QIODevice::ReadOnly)) continue;

        QDataStream stream(&lock);
        QString instanceId, storedPath;
        stream >> instanceId >> storedPath;
        if (stream.status() != QDataStream::Ok) continue;

        if (storedPath == wantPath) {
            matches.append({QFileInfo(lockPath).lastModified(), byId.filePath(id) + "/ipc.sock"});
        }
    }

    std::sort(matches.begin(), matches.end(), [](const auto& a, const auto& b) {
        return a.first > b.first;
    });

    QStringList result;
    for (const auto& m : matches) result.append(m.second);
    return result;
}

// ---- ARGV SHAPE MATCHES `qs` EXACTLY, ON PURPOSE ----
//
// Not `qsipc <config-path> <target> <function> [args...]`, even though
// that would be simpler to parse. cheatsheet.py generates every bind's
// on-screen label by pattern-matching the literal substring " ipc call "
// in its exec string (see cheatsheet.py's own use of
// `arg.split(" ipc call ", 1)`) -- a bind rewritten to drop that text
// would silently fall back to showing the raw command instead of a real
// label, the exact class of regression this file's own history already
// records once for `bar-action` (commit 966673b, "the rofi/chord mode
// HUD said 'bar action' 26 times"). Keeping `-p <path> ipc call <target>
// <function> [args...]` means every call site becomes a pure binary-name
// swap -- `s/^qs /qsipc /` -- with nothing downstream needing to change.
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);

    // strcmp, not QString ==, against a string literal: the implicit
    // QString(const char*) + operator== path hits the same GCC-16 /
    // packaged-Qt6 ABI mismatch as qUtf8Printable did above (a copy
    // relocation against a protected QString::_empty symbol).
    bool usageOk = argc >= 7 && std::strcmp(argv[1], "-p") == 0
        && std::strcmp(argv[3], "ipc") == 0 && std::strcmp(argv[4], "call") == 0;
    if (!usageOk) {
        fprintf(stderr, "usage: qsipc -p <config-path> ipc call <target> <function> [args...]\n");
        return 2;
    }

    QString configPath = argv[2];
    QString target = argv[5];
    QString function = argv[6];
    QVector<QString> arguments;
    for (int i = 7; i < argc; i++) arguments.append(QString::fromLocal8Bit(argv[i]));

    QStringList candidates = resolveSocketCandidates(configPath);
    if (candidates.isEmpty()) {
        fprintf(stderr, "qsipc: no running instance found for %s\n", argv[2]);
        return 1;
    }

    QLocalSocket sock;
    QString sockPath;
    for (const auto& candidate : candidates) {
        sock.connectToServer(candidate);
        if (sock.waitForConnected(500)) {
            sockPath = candidate;
            break;
        }
        sock.abort();
    }
    if (sockPath.isEmpty()) {
        QTextStream(stderr) << "qsipc: no live instance among " << candidates.size()
                             << " registered for " << configPath << Qt::endl;
        return 1;
    }

    QDataStream stream(&sock);

    stream << static_cast<quint8>(3); // StringCallCommand's index in IpcCommand
    stream << target;
    stream << function;
    stream << arguments;
    sock.flush();

    while (true) {
        if (sock.bytesAvailable() == 0 && !sock.waitForReadyRead(2000)) {
            fprintf(stderr, "qsipc: no response\n");
            return 1;
        }

        stream.startTransaction();
        quint8 tag = 0;
        stream >> tag;

        bool isVoid = true;
        QString returnValue;
        if (tag == 5) { // Completed
            stream >> isVoid;
            stream >> returnValue;
        }

        if (!stream.commitTransaction()) continue;

        switch (tag) {
            case 5:
                if (!isVoid && !returnValue.isEmpty())
                    QTextStream(stdout) << returnValue << Qt::endl;
                return 0;
            case 1:
                fprintf(stderr, "qsipc: no current generation\n");
                return 1;
            case 2:
                fprintf(stderr, "qsipc: target not found: %s\n", argv[5]);
                return 1;
            case 3:
                fprintf(stderr, "qsipc: function not found: %s.%s\n", argv[5], argv[6]);
                return 1;
            case 4:
                fprintf(stderr, "qsipc: argument parse failed calling %s.%s\n", argv[5], argv[6]);
                return 1;
            default:
                fprintf(stderr, "qsipc: unexpected response tag %d\n", tag);
                return 1;
        }
    }
}
