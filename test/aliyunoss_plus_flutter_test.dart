import 'package:flutter_test/flutter_test.dart';

import 'package:aliyunoss_plus_flutter/aliyunoss_plus_flutter.dart';

void main() {
  test('adds one to input values', () {
    AliyunOssClient client = AliyunOssClient(
      accessKeyId: 'accessKeyId',
      accessKeySecret: 'accessKeySecret',
      securityToken: 'securityToken',
    );
    AliyunOssConfig config = AliyunOssConfig(
      endpoint: 'endpoint',
      bucket: 'bucket',
      directory: 'directory',
      domain: 'https://bucket.endpoint',
    );
    client.upload(id: "testid", config: config, ossFileName: "xxx.jpg",filePath: "xxx/xxxx/abc.jpg");
  });
}
