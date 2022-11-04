<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

## 阿里云oss,目前最好用的库,没有之一.终于为杂乱无章的非官方库画上句号!

## Features

Upload to the aliyun_oss . It can be a video, a picture, or something else

## Getting started

### Install
```
aliyunoss_plus_flutter: ^1.0.0
```

## Usage

```dart
import 'package:aliyunoss_plus_flutter/aliyunoss_plus_flutter.dart';
import 'package:flutter/material.dart';

class AliyunPage extends StatefulWidget {
  const AliyunPage({super.key});

  @override
  State<AliyunPage> createState() => _AliyunPageState();
}

class _AliyunPageState extends State<AliyunPage> {
  String filePath = "/Users/xxx/Downloads/video.mp4";
  late AliyunOssClient client;
  late AliyunOssConfig config;

  final String uploadId1 = "test-1";
  final String uploadId2 = "test-2";
  String showText = "准备上传";
  @override
  void initState() {
    client = AliyunOssClient(
        accessKeyId: "STS.NSkZtxxxxxxxE",
        accessKeySecret: "77XxxxxXXXXXXXXXXXXXXXXXXXXXXtFv",
        securityToken:
            "CAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX==");
    config = AliyunOssConfig(
        endpoint: "https://oss-cn-shanghai.aliyuncs.com",
        bucket: "pvideo-xxx",
        directory: "dev-nom/20221103/");

    AliyunOssClient.eventStream.listen((event) {
      print("eventStream:${event.toString()}");
      if (mounted) {
        setState(() {
          showText = event.toString();
        });
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('AliyunPage'),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              'filePath: $filePath',
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              ElevatedButton(
                onPressed: () async {
                  final res = await client.upload(
                      id: uploadId1, config: config, filePath: filePath);
                  print("result:${res.toString()}");
                },
                child: const Text('直接上传'),
              ),
              ElevatedButton(
                onPressed: () async {
                  client.uploadMultipart(
                      id: uploadId2, config: config, filePath: filePath);
                },
                child: const Text('分片上传'),
              ),
              ElevatedButton(
                onPressed: () async {
                  AliyunOssClient.cancelTask(uploadId2);
                },
                child: const Text('暂停上传'),
              ),
              ElevatedButton(
                onPressed: () async {
                  client.resumeUpload(uploadId2);
                },
                child: const Text('恢复上传'),
              ),
            ]),
            Text(showText),
          ],
        ));
  }
}

```


