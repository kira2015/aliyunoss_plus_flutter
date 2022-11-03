import 'dart:async';
import 'dart:convert';

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:xml/xml.dart';
import '../aliyunoss_plus_flutter.dart';
import 'aliyunoss_utils.dart';

class AliyunOssClient {
  // 鉴权信息
  late String accessKeyId;
  late String securityToken;
  late String accessKeySecret;

  AliyunOssClient(
      {required this.accessKeyId,
      required this.securityToken,
      required this.accessKeySecret});
  static final StreamController<AliyunOssResult> _controller =
      StreamController.broadcast();

  ///eventStream 监听上传进度、结果
  ///@param--->>
  ///id:上传的任务id 唯一标识
  ///state上传状态 fail:上传失败 success:上传成功  uploading:上传中
  ///url:上传成功后的url
  ///msg:上传中的信息
  ///count:已经上传的大小
  ///total:文件大小
  ///partInfo:上传失败时会返回分片信息,用于断点续传
  static Stream<AliyunOssResult> get eventStream => _controller.stream;

  //任务队列
  static final Map<String, CancelToken> _taskMap = {};

  ///任务取消
  static void cancelTask(String id) {
    if (_taskMap.containsKey(id)) {
      _taskMap[id]!.cancel("任务取消/暂停");
      _taskMap.remove(id);
    }
  }

  ///恢复上传,断点续传
  void resumeUpload(String id) async {
    AliyunOssPartInfo? partInfo = await getPartInfo(id);
    if (partInfo != null) {
      _uploadPartInfo(partInfo, id: id);
    } else {
      _controller.sink.add(AliyunOssResult(
          id: id, state: AliyunOssResultState.fail, msg: "本地数据不存在,请重新上传"));
    }
  }

  ///快速单个上传
  ///[id] 任务id 唯一标识
  ///[config] 阿里云鉴权信息
  ///[filePath] 文件路径
  ///[buffer] 文件数据 ,必须与ossFileName配合使用
  ///[ossFileName] oss上的文件名(如xxx.jpg) 不传默认为路径的文件名
  ///[fileNameSuffix] 返回上传文件路径时,添加文件后缀
  /// filePath与buffer不能同时为空;两者皆有时,filePath优先;filePath为空时,ossFileName不能为空;
  Future<AliyunOssResult> upload(
      {required String id,
      required AliyunOssConfig config,
      String? ossFileName,
      String? filePath,
      Uint8List? buffer,
      String? fileNameSuffix}) async {
    assert(filePath != null || (buffer != null && ossFileName != null));
    ossFileName ??= filePath!.split("/").last;

    String objectPath = "${config.directory}$ossFileName";

    // 转化data
    try {
      String contentMD5 = "";
      int contentLength = 0;
      dynamic data;

      // 获取文件内容
      if (filePath != null) {
        final file = File(filePath);
        final exists = await file.exists();
        final fileLength = await file.length();
        if (exists == false || fileLength <= 0) {
          return AliyunOssResult(
              id: id, state: AliyunOssResultState.fail, msg: "文件不存在");
        }

        contentMD5 = base64Encode(md5.convert(file.readAsBytesSync()).bytes);
        contentLength = fileLength;
        data = file.openRead();
      } else if (buffer?.isNotEmpty == true) {
        // 获取buffer内容
        contentMD5 = base64Encode(md5.convert(buffer!).bytes);
        contentLength = buffer.length;
        data = Stream.fromIterable(buffer.map((e) => [e]));
      } else {
        return AliyunOssResult(
            id: id, state: AliyunOssResultState.fail, msg: "文件或者数据不存在");
      }

      // 上传的到阿里云的地址
      final String requestUrl =
          'https://${config.bucket}.${config.endpoint}/$objectPath';

      // 访问数据时的域名地址
      String finallyUrl = '${config.domain}/$objectPath';
      // 增加名字后缀
      finallyUrl = addSuffix(finallyUrl, fileNameSuffix);

      // 请求时间
      final date = requestTime();
      // 请求头
      Map<String, String> headers = {
        'Content-Type':
            lookupMimeType(filePath ?? "") ?? "application/octet-stream",
        'Content-Length': contentLength.toString(),
        'Content-MD5': contentMD5,
        'Date': date,
        'Host': "${config.bucket}.${config.endpoint}",
        "x-oss-security-token": securityToken,
      };
      headers["Authorization"] =
          sign(headers: headers, objectPath: objectPath, bucket: config.bucket);

      final cancelToken = CancelToken();
      _taskMap[id] = cancelToken;
      await Dio(BaseOptions(
              connectTimeout: AliyunOssHttp.connectTimeout,
              sendTimeout: AliyunOssHttp.sendTimeout,
              receiveTimeout: AliyunOssHttp.receiveTimeout))
          .put(requestUrl,
              data: data,
              options:
                  Options(headers: headers, responseType: ResponseType.plain),
              cancelToken: cancelToken, onSendProgress: (count, total) {
        if (count == total) {
          _controller.sink.add(AliyunOssResult(
              id: id,
              state: AliyunOssResultState.success,
              url: finallyUrl,
              count: count,
              total: total));
        } else {
          _controller.sink.add(AliyunOssResult(
              id: id,
              state: AliyunOssResultState.uploading,
              count: count,
              total: total));
        }
      });
      _taskMap.remove(id);
      return AliyunOssResult(
          id: id, state: AliyunOssResultState.success, url: finallyUrl);
    } catch (e) {
      // 上传失败
      _taskMap.remove(id);
      return AliyunOssResult(
          id: id, state: AliyunOssResultState.fail, msg: e.toString());
    }
  }

  //分片上传---->
  //第一步 InitiateMultipartUploadResult

  /// 分段上传
  ///[id] 任务id 唯一标识 可用于断点续传
  ///[config] 阿里云鉴权信息
  ///[filePath] 文件路径(如xxx/xxx.jpg)
  ///[ossFileName] oss上的文件名(如xxx.jpg) 不传默认为路径的文件名
  ///[fileNameSuffix] 返回上传文件路径时,添加文件后缀
  void uploadMultipart(
      {required String id,
      required AliyunOssConfig config,
      required String filePath,
      String? ossFileName,
      String? fileNameSuffix}) async {
    ossFileName ??= filePath.split("/").last;
    String objectPath = "${config.directory}$ossFileName";
    int contentLength = 0;
    final file = File(filePath);
    final exists = await file.exists();
    contentLength = await file.length();

    if (exists == false || contentLength <= 0) {
      _controller.sink.add(AliyunOssResult(
          state: AliyunOssResultState.fail, msg: "文件不存在", id: id));
      return;
    }

    // 上传的到阿里云的地址
    final String requestUrl =
        'https://${config.bucket}.${config.endpoint}/$objectPath?uploads';

    // 请求时间
    final date = requestTime();
    // 请求头
    Map<String, String> headers = {
      'Content-Type': lookupMimeType(filePath) ?? "application/octet-stream",
      'Date': date,
      'Host': "${config.bucket}.${config.endpoint}",
      "x-oss-security-token": securityToken,
    };
    headers["Authorization"] = sign(
        headers: headers,
        objectPath: "$objectPath?uploads",
        bucket: config.bucket,
        httpMethod: "POST");

    String uploadId = "";
    try {
      final result = await Dio(BaseOptions(
              connectTimeout: AliyunOssHttp.connectTimeout,
              sendTimeout: AliyunOssHttp.sendTimeout,
              receiveTimeout: AliyunOssHttp.receiveTimeout))
          .post<String>(requestUrl,
              options:
                  Options(headers: headers, responseType: ResponseType.plain));
      if (stateCodePass(result.statusCode)) {
        final xml = XmlDocument.parse(result.data ?? "");
        final uploadIdList = xml.findAllElements("UploadId");
        if (uploadIdList.isEmpty || uploadIdList.first.text.isEmpty) {
          _controller.sink.add(AliyunOssResult(
              state: AliyunOssResultState.fail, msg: "分片uploadId为空", id: id));
          return;
        }
        _controller.sink.add(AliyunOssResult(
            state: AliyunOssResultState.uploading, msg: "分片成功", id: id));
        uploadId = uploadIdList.first.text;
      }
    } catch (e) {
      _controller.sink.add(AliyunOssResult(
          state: AliyunOssResultState.fail, msg: "分片失败$e,请检查鉴权信息与网络", id: id));
      return;
    }

    // 计算分片
    List<AliyunOssPart> ossPartList = calculateParts(contentLength);

    AliyunOssPartInfo partInfo = AliyunOssPartInfo(
        bucket: config.bucket,
        endpoint: config.endpoint,
        objectPath: objectPath,
        filePath: filePath,
        uploadId: uploadId,
        domain: config.domain,
        total: contentLength,
        fileNameSuffix: fileNameSuffix);
    partInfo.parts = ossPartList;

    _uploadPartInfo(partInfo, id: id);
  }

  //第二步 上传分片

  ///分片上传 续传
  ///[partInfo] 分片信息
  ///[id] 任务id
  void _uploadPartInfo(AliyunOssPartInfo partInfo, {required String id}) async {
    // 获取文件内容
    final file = File(partInfo.filePath);
    final exists = await file.exists();

    if (exists == false) {
      _controller.sink.add(AliyunOssResult(
          state: AliyunOssResultState.fail,
          msg: "文件不存在",
          id: id,
          partInfo: partInfo));
      return;
    }
    // 管理任务
    CancelToken cancelToken = CancelToken();
    _taskMap[id] = cancelToken;
    bool conditionUpload = true;
    Future handle(AliyunOssPart part) async {
      try {
        dynamic data = File(partInfo.filePath).openRead(
            part.partRangeStart, part.partRangeStart + part.partRangeLength);

        // 上传的到阿里云的地址
        final String partParams =
            "partNumber=${part.partNumber}&uploadId=${partInfo.uploadId}";
        final String requestUrl =
            'https://${partInfo.bucket}.${partInfo.endpoint}/${partInfo.objectPath}?$partParams';

        // 请求时间
        final date = requestTime();

        // 请求头
        Map<String, String> headers = {
          'Content-Length': part.partRangeLength.toString(),
          'Content-Type': 'application/octet-stream',
          'Date': date,
          'Host': "${partInfo.bucket}.${partInfo.endpoint}",
          "x-oss-security-token": securityToken,
        };

        // 计算签名
        headers["Authorization"] = sign(
            headers: headers,
            objectPath: "${partInfo.objectPath}?$partParams",
            bucket: partInfo.bucket);

        // 开始上传
        final result = await Dio(BaseOptions(
                connectTimeout: AliyunOssHttp.connectTimeout,
                sendTimeout: AliyunOssHttp.sendTimeout,
                receiveTimeout: AliyunOssHttp.receiveTimeout))
            .put<String>(
          requestUrl,
          data: data,
          cancelToken: cancelToken,
          options: Options(headers: headers, responseType: ResponseType.plain),
          onSendProgress: (int count, int total) {
            // 上传进度
            int progress = partInfo.progress + count;

            _controller.sink.add(AliyunOssResult(
                state: AliyunOssResultState.uploading,
                id: id,
                count: progress,
                total: partInfo.total));
          },
        );

        final eTag = result.headers.map['ETag'];

        if (stateCodePass(result.statusCode) && eTag?.isNotEmpty == true) {
          // 上传成功
          String eTagKey = eTag!.first.toString();
          part.partETag = eTagKey;
          partInfo.progress = partInfo.progress + part.partRangeLength;
        } else {
          // 上传失败-----
          //本地化
          String json = partInfo.toEncodeString();
          await keyStoreSave(id, json);

          _controller.sink.add(AliyunOssResult(
              state: AliyunOssResultState.fail,
              msg: "上传失败",
              id: id,
              partInfo: partInfo));
        }
      } catch (e) {
        conditionUpload = false;
        //本地化
          String json = partInfo.toEncodeString();
          await keyStoreSave(id, json);
        // 上传失败
        _controller.sink.add(AliyunOssResult(
            state: AliyunOssResultState.fail,
            msg: "$e",
            id: id,
            partInfo: partInfo));
      }
    }

    Iterator<AliyunOssPart> iterator =
        partInfo.parts.where((element) => element.partETag == null).iterator;
    while (conditionUpload && iterator.moveNext()) {
      await handle(iterator.current);
    }

    // 所有分片上传完成
    if (conditionUpload) {
      _mergeCommit(partInfo: partInfo, id: id);
    }
  }

  //分片上传--第三步
  ///合并分片提交
  void _mergeCommit(
      {required AliyunOssPartInfo partInfo, required String id}) async {
    try {
      final sb = StringBuffer();
      sb.write('<CompleteMultipartUpload>');
      for (final part in partInfo.parts) {
        sb.write("<Part>");
        sb.write("<PartNumber>${part.partNumber}</PartNumber>");
        sb.write("<ETag>${part.partETag}</ETag>");
        sb.write("</Part>");
      }
      sb.write('</CompleteMultipartUpload>');
      final xml = XmlDocument.parse(sb.toString()).toXmlString(pretty: true);

      final rawData = Uint8List.fromList(utf8.encode(xml));
      final data = Stream.fromIterable(
          Uint8List.fromList(utf8.encode(xml)).map((e) => [e]));

      // 上传到阿里云的地址
      final String requestUrl =
          'https://${partInfo.bucket}.${partInfo.endpoint}/${partInfo.objectPath}?uploadId=${partInfo.uploadId}';

      String contentMD5 = base64Encode(md5.convert(rawData).bytes);

      // 请求时间
      final date = requestTime();

      // 请求头
      Map<String, String> headers = {
        'content-length': rawData.length.toString(),
        'content-type': 'application/xml',
        'content-md5': contentMD5,
        'Date': date,
        'Host': "${partInfo.bucket}.${partInfo.endpoint}",
        "x-oss-security-token": securityToken,
      };

      // 计算签名
      headers["Authorization"] = sign(
          headers: headers,
          objectPath: "${partInfo.objectPath}?uploadId=${partInfo.uploadId}",
          bucket: partInfo.bucket,
          httpMethod: 'POST');

      // 提交请求
      final result = await Dio(BaseOptions(
              connectTimeout: AliyunOssHttp.connectTimeout,
              sendTimeout: AliyunOssHttp.sendTimeout,
              receiveTimeout: AliyunOssHttp.receiveTimeout))
          .post<void>(
        requestUrl,
        data: data,
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
      if (stateCodePass(result.statusCode)) {
        String domain;
        if (partInfo.domain != null) {
          domain = partInfo.domain!;
        } else {
          domain = "https://${partInfo.bucket}.${partInfo.endpoint}";
        }

        // 访问数据时的域名地址
        String url = '$domain/${partInfo.objectPath}';
        url = addSuffix(url, partInfo.fileNameSuffix);

        // 上传成功
        _controller.sink.add(AliyunOssResult(
            state: AliyunOssResultState.success,
            id: id,
            url: url,
            total: partInfo.total,
            count: partInfo.progress));
      } else {
        // 上传失败
        _controller.sink.add(AliyunOssResult(
            state: AliyunOssResultState.fail,
            msg: "合并上传失败",
            id: id,
            partInfo: partInfo));
        String json = partInfo.toEncodeString();
        await keyStoreSave(id, json);
      }
    } catch (e) {
      // 上传失败
      _controller.sink.add(AliyunOssResult(
          state: AliyunOssResultState.fail,
          msg: "$e",
          id: id,
          partInfo: partInfo));
    }
  }
}
