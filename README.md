# PhotoLink PC（图联 · 桌面端）

局域网发现手机、浏览相册、下载原图、删除、拖拽上传。

## 运行

```bash
flutter pub get
flutter run -d windows
```

## 目录

- `lib/services/mdns_discovery_service.dart` — mDNS 发现
- `lib/services/gallery_api_service.dart` — 调用手机 API
- `lib/pages/device_list_page.dart` — 设备列表 / 手动连接
- `lib/pages/gallery_page.dart` — 相册网格与任务队列
