import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:filesize/filesize.dart';
import 'package:dio/dio.dart';
import 'package:pedantic/pedantic.dart';
import 'models/filesystem.dart';
import 'file_icons.dart';
import 'downloader.dart';
import 'commands.dart';
import 'state.dart';
import 'log.dart';

class _RemoteFileExplorerState extends State<RemoteFileExplorer> {
  SlidableController _slidableController;

  @override
  void initState() {
    getData();
    super.initState();
  }

  List<Widget> buildListing(BuildContext context) {
    var w = <Widget>[];
    if (state.remotePath != "/" && state.remotePath != "")
      w.add(GestureDetector(
        child: ListTile(
          leading: const Icon(Icons.arrow_upward),
          title: const Text("..", textScaleFactor: 1.5),
        ),
        onTap: () {
          var li = state.remotePath.split("/");
          li.removeLast();
          state.remotePath = li.join("/");
          getData();
        },
      ));
    for (var dir in state.remoteDirectoryListing.directories) {
      w.add(GestureDetector(
        child: ListTile(
            dense: true,
            leading: const Icon(Icons.folder, color: Colors.orange),
            title: Text(dir.name)),
        onTap: () {
          String p;
          (state.remotePath != "/" && state.remotePath != "")
              ? p = state.remotePath + "/" + dir.name
              : p = "/" + dir.name;
          state.remotePath = p;
          //print("REQUEST ${state.remotePath}");
          getData();
        },
      ));
    }
    for (var file in state.remoteDirectoryListing.files) {
      w.add(Slidable(
        key: Key(file.name),
        controller: _slidableController,
        direction: Axis.horizontal,
        actionPane: SlidableBehindActionPane(),
        actionExtentRatio: 0.25,
        child: ListTile(
            dense: true,
            trailing: Text(filesize(file.size)),
            leading: setFileIcon(file.name),
            title: Text(file.name)),
        actions: [
          IconSlideAction(
            caption: 'Download',
            color: Colors.blue,
            icon: Icons.file_download,
            onTap: () {
              log.infoFlash("Downloading file");
              String rp;
              (state.remotePath == "/" || state.remotePath == "")
                  ? rp = ""
                  : rp = state.remotePath;
              //(state.remotePath == "/") ? _path = "" : _path = state.remotePath;
              String url = state.activeDataLink.address + rp + "/" + file.name;
              var dl = Downloader();
              String initialPath = state.localPath;
              dl.download(url, state.localPath, context);
              dl.completedController.listen((_) {
                dl.dispose();
                // refresh the ui if still in the same directory
                if (initialPath == state.localPath) lsDir();
                log.infoFlash("Download completed");
              });
            },
          )
        ],
      ));
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    Widget w;
    (state.remoteDirectoryListing != null)
        ? w = ListView(children: buildListing(context))
        : w = Center(child: const CircularProgressIndicator());
    return w;
  }

  Future<void> getData() async {
    final dynamic err = await fetchData(state.remotePath);
    if (err != null) {
      final msg = "Can not connect to server: $err";
      unawaited(log.errorFlash(msg));
      state.remoteViewActive = false;
      try {
        await Navigator.of(context).pushReplacementNamed("/file_explorer");
      } catch (e) {
        // The user has moved to another page in between
      }
    }
  }

  Future<dynamic> fetchData(String _remotePath) async {
    assert(state.activeDataLink != null);
    assert(state.httpClient != null);
    unawaited(log.debug("GET ${state.activeDataLink.address}"));
    unawaited(log.debug("PATH $_remotePath"));
    try {
      final formData = FormData.from(<String, dynamic>{"path": _remotePath});
      final response = await state.httpClient.post<Map<String, dynamic>>(
          "${state.activeDataLink.address}/ls",
          data: formData);
      print("FORM DATA: $formData");
      print("RESPONSE DATA: ${response.data}");
      state.setRemoteDirectoryListing(
          RemoteDirectoryListing.fromJson(response.data));
    } on DioError catch (e) {
      return e;
    } catch (e) {
      return e;
    }
    return null;
  }
}

class RemoteFileExplorer extends StatefulWidget {
  @override
  _RemoteFileExplorerState createState() => _RemoteFileExplorerState();
}
