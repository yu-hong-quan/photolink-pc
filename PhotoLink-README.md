# PhotoLink · 图联

局域网相册互联工具：**手机提供相册服务，电脑发现并浏览 / 下载 / 整理**。适合同一 Wi‑Fi 下快速把手机照片传到电脑处理，无需数据线、不经过公网。

| 端   | 仓库                                                             | 说明                                      |
| --- | -------------------------------------------------------------- | --------------------------------------- |
| 手机  | [photolink-app](https://github.com/yu-hong-quan/photolink-app) | Android / iOS：相册 HTTPS + mDNS；可搜电脑或扫码配对 |
| 电脑  | [photolink-pc](https://github.com/yu-hong-quan/photolink-pc)   | Windows / macOS：发现手机、相册浏览、回收站、托盘        |

本地工作区路径（开发机）：

- `photolink-app/`
- `photolink-pc/`

---

## 产品能力

- 局域网发现（mDNS `_photolink._tcp`）与扫码 / 搜索配对
- 配对成功后电脑**自动连接**并打开相册
- 相册懒加载、原图预览、下载、拖拽上传
- 软删除回收站（手机本地备份；撤回写回系统相册）
- 重命名 / 归类同步
- 本地 / 测试 / 生产三套端口环境
- 关于作者页；电脑端系统托盘

---

## 界面预览（手机端）

### 已连接电脑

![App 首页已连接](./photolink-app/docs/screenshots/app-home-connected.png)

### 关于作者

![App 关于作者](./photolink-app/docs/screenshots/app-about.png)

更多说明见 [photolink-app/README.md](./photolink-app/README.md)。

---

## 界面预览（电脑端）

### 设备列表与扫码配对

![PC 设备列表](./photolink-pc/docs/screenshots/pc-device-list.png)

### 相册浏览

![PC 相册](./photolink-pc/docs/screenshots/pc-gallery.png)

更多说明见 [photolink-pc/README.md](./photolink-pc/README.md)。

---

## 架构示意

```text
┌──────────── App（手机）────────────┐     ┌──────────── PC（电脑）────────────┐
│ HTTPS 相册 :galleryPort            │◄────│ 浏览 / 下载 / 上传 / 回收站        │
│ mDNS 广播 deviceType=phone         │     │ mDNS 发现手机                      │
│ 搜索电脑 / 扫码 → POST /api/pair   │────►│ HTTPS 配对 :pairPort + 二维码      │
│                                    │     │ mDNS 广播 deviceType=pc            │
└────────────────────────────────────┘     └────────────────────────────────────┘
```

两端 **FLAVOR 必须一致**，否则端口对不上无法配对。

| FLAVOR   | 相册端口  | 配对端口  |
| -------- | ----- | ----- |
| local    | 53337 | 53338 |
| test     | 53327 | 53328 |
| prod（默认） | 53317 | 53318 |

---

## 快速开始

### 手机

```bash
cd photolink-app
flutter pub get
flutter run --dart-define=FLAVOR=local
# 或 .\scripts\run-android.ps1 -Env local
```

### 电脑

```bash
cd photolink-pc
flutter pub get
flutter run -d windows --dart-define=FLAVOR=local
# 或 .\scripts\run-windows.ps1 -Env local
```

详细运行、打包、目录说明见各仓库 README：

- [photolink-app/README.md](./photolink-app/README.md)
- [photolink-pc/README.md](./photolink-pc/README.md)

---

## 推荐使用流程

1. 手机、电脑连同一 Wi‑Fi，均以相同 FLAVOR 启动。
2. 手机保持前台；电脑打开后等待扫描或展示二维码。
3. 手机「搜索附近电脑」点连接，或扫电脑二维码。
4. 电脑自动进入相册，即可浏览与传输。

---

## 多设备现状

- 电脑设备列表可显示多台手机；**同时浏览相册以一台为主**。
- 手机服务可被多台电脑访问；首页连接态展示最近活跃电脑。

---

## 作者

余洪全（yu-hong-quan）· https://github.com/yu-hong-quan
