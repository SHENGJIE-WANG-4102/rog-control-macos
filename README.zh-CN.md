# ROG Control for macOS

简体中文 · [English](README.md) · **v0.1** · [更新日志](CHANGELOG.zh-CN.md)

面向 **ASUS ROG 枪神 9 系列**的原生 macOS 控制中心：原厂性能档位、风扇监控，以及 CPU／GPU 传感器视图。

**支持 ROG 枪神 9 系列，但目前仅在 G815LW 上做过实机测试。** 其他型号与 BIOS 版本尚未验证，可能需要补充已审查的固件配置后才能使用模式控制。

**当前为实验性早期版本。** 原厂档位控制已在 macOS 26 下的 ROG Strix G18 **G815LW（枪神 9）** 上实机验证。固件桥接驱动只接受一份已审查的 DSDT 指纹，并不是通用 ROG 驱动。本项目由社区独立开发，并非 ASUS 官方产品。

## 功能状态

| 功能 | 当前状态 |
| --- | --- |
| 安静／性能／Turbo 三档 | 已实测，确认固件档位读回和风扇转速变化 |
| CPU、GPU、第三风扇转速 | 已实测；应用可见时支持每秒刷新 |
| CPU 温度 | 读取已有 SMC 温度传感器 |
| CPU 封装功耗 | 读取封装能耗对应的 SMC 项，不混用核心域功耗 |
| CPU 频率 | 尝试读取 `powermetrics` 的采样平均频率；系统不提供时显示不可用 |
| GPU 频率、功耗、温度 | 已提供显示位置；本项目尚未适配测试所用 NVIDIA RM 监控后端，温度有可用 SMC 提供者时才显示 |
| 授权 | 安装控制组件时授权一次，后续打开软件自动连接 |
| 自定义功耗上限／风扇曲线 | 尚未启用 |
| 亮度、键盘灯 | 尚未实现 |

缺失的传感器数据会明确显示为“不可用”，不会填入估算的额定值。CPU 功耗是传感器导出的封装功耗估计，不代表整机插座功耗；平均频率也不代表最快核心的瞬时峰值。

原厂档位可影响固件的控制策略，但这不等于已经验证了自定义 PL1／PL2 或 GPU TGP 调节。

## 构建和运行

需要 Intel macOS 环境及 Xcode Command Line Tools。应用使用系统的 AppKit、Foundation、IOKit 和 Security 框架，无需额外包管理器依赖。

```sh
xcode-select --install
./script/build_and_run.sh
```

构建结果位于 `dist/ROG Control for macOS.app`。只编译、不打开窗口：

```sh
./script/build_and_run.sh --build-only
```

还支持 `--verify`、`--debug`、`--logs`、`--telemetry`。

当前应用要求已经加载兼容的 `ROGFirmwareProbe` **1.3.0**。构建或打开应用不会安装内核扩展、重建系统缓存、修改 EFI 或启动参数。

### 固件桥接驱动

`Driver/` 包含桥接驱动源码与元数据，需要单独获取 [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK)：

```sh
git clone https://github.com/acidanthera/MacKernelSDK.git Vendor/MacKernelSDK
./Driver/build.sh
```

也可通过环境变量 `MAC_KERNEL_SDK` 指定已有 SDK。脚本只生成本地 kext，不自动安装：内核扩展的部署与恢复取决于具体引导环境。不要直接删除固件指纹校验来尝试未经审查的机型。

已审查的机型与固件信息集中在 `Driver/Profiles.hpp`。系列名称不等于兼容性校验；新增条目前需要审查对应机器的固件并验证接口行为。

保留 `ROGFirmwareProbe` 名称是为了兼容已经实测的驱动接口。

## 使用方法

1. 确认匹配的桥接驱动已加载，打开应用。
2. 点击“授权一次…”，在 macOS 原生对话框中完成管理员授权，安装控制组件。
3. 选择安静、性能或 Turbo，点击“应用档位”。仅接通电源时允许切换，切换后读回固件状态确认。
4. 按需启用或关闭自动读取。关闭应用会停止界面轮询，所选原厂档位保留。

后台组件随系统启动后只等待请求，不会在空闲启动路径读取固件、采样传感器或自动切档。它只接受指定用户运行的、代码签名身份经过批准的 GUI 请求。签名检查、本地套接字权限、固件指纹和档位范围校验分别限制调用范围。重新编译后应用代码身份改变，更新控制组件时可能需要再次授权。

本地开发构建采用临时签名，未进行公证。当前界面为中文，项目提供中英文说明。

### 卸载控制组件

```sh
sudo /Library/PrivilegedHelperTools/com.macdriver.ROGControlHelper --uninstall
```

这会移除用户态控制服务，不移除单独安装的桥接驱动，也不改变当前原厂档位。应用本身可另行移除。

## 验证

```sh
./script/test.sh
```

这些测试检查请求边界，并在主机模拟环境中运行实际固件命令函数，不代表固件一定响应或其他机型兼容。实机已经验证安静、性能两档切换、三个风扇转速读数，以及恢复到测试前的 Turbo 档。

固件调用是同步执行的，用户态超时不能取消卡住的 ACPI／SMI 调用。驱动在 `start`、`stop`、`free` 中均不调用固件；写入只通过明确请求触发，并限制在原厂档位端点，不开放任意 ACPI、EC、MSR 访问。自定义曲线、功耗路径仍待进一步验证。

## 目录

- `Sources/`：原生应用、管理员组件、传感器读取与桥接客户端。
- `Driver/`：限定机型的固件桥接驱动。
- `Tools/`：桥接命令行客户端。
- `Tests/`：无需真实固件调用的命令边界与错误处理测试。
- `script/`：统一构建、运行、测试入口。

项目不包含个人诊断日志、系统备份、显卡驱动、固件表转储或 EFI 配置。

## 许可证与参考

本项目原创代码采用 [MIT](LICENSE)。依赖和单独安装的驱动保留各自许可证，不随本项目重新授权或打包。详见 [THIRD_PARTY.md](THIRD_PARTY.md)。

[项目仓库](https://github.com/SHENGJIE-WANG-4102/rog-control-macos)
