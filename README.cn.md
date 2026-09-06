# argon2 — 跨平台预编译二进制

[![build-and-test](https://github.com/x-cmd-build/argon2/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/x-cmd-build/argon2/actions/workflows/build-and-test.yml)

[Argon2][upstream] 参考实现命令行工具的跨平台构建。Argon2 是 2015 年
[密码哈希竞赛][phc] (Password Hashing Competition) 的冠军算法。

八个目标平台，全部由一台 Linux runner 用 `zig cc` 交叉编译产出。不需要
Alpine 容器，不需要 macOS runner，不需要 MSYS2。

*[English](README.md)*

## 安装

```sh
x eget x-cmd-build/argon2
```

或者从 [Releases][releases] 下载压缩包，把其中的 `bin/` 加进 PATH：

```sh
tar -xJf argon2-linux-x64-musl.tar.xz
export PATH="$PWD/argon2-linux-x64-musl/bin:$PATH"
argon2 --help
```

## 使用

argon2 从 stdin 读密码，第一个参数是盐值：

```sh
# 计算哈希 (Argon2id, 2 轮, 2^16 KiB = 64 MiB 内存, 1 并行度)
printf 'password' | argon2 somesalt -id -t 2 -m 16 -p 1

# 只输出编码后的哈希 —— 存进数据库的就是这一串
printf 'password' | argon2 somesalt -id -t 2 -m 16 -p 1 -e
$argon2id$v=19$m=65536,t=2,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc

# 只输出原始哈希
printf 'password' | argon2 somesalt -id -t 2 -m 16 -p 1 -r
```

`-i` 选 Argon2i（数据无关，默认），`-d` 选 Argon2d（数据相关），`-id` 选
Argon2id（混合模式 —— 没有特殊理由就用这个）。完整参数见 `argon2 -h`，
或用压缩包里 `share/man/man1/argon2.1` 的 man 手册。

## 目标平台

| 文件 | 系统 / 架构 | libc | 链接方式 |
|---|---|---|---|
| `argon2-linux-x64-musl.tar.xz` | Linux x86-64 | musl | 静态 |
| `argon2-linux-x64-gnu.tar.xz` | Linux x86-64 | glibc ≥ 2.17 | 动态 |
| `argon2-linux-arm64-musl.tar.xz` | Linux aarch64 | musl | 静态 |
| `argon2-linux-arm64-gnu.tar.xz` | Linux aarch64 | glibc ≥ 2.17 | 动态 |
| `argon2-darwin-x64.tar.xz` | macOS x86-64 | libSystem | 动态 |
| `argon2-darwin-arm64.tar.xz` | macOS aarch64 | libSystem | 动态 |
| `argon2-win-x64-mingw.zip` | Windows x86-64 | mingw-w64 | 静态 |
| `argon2-win-arm64-mingw.zip` | Windows aarch64 | mingw-w64 | 静态 |

musl 版本是完全静态链接的，不依赖发行版的 glibc 版本，任何 Linux 上都能跑。
glibc 版本锁定在 2.17 ABI（RHEL 7 时代），体积更小。

Windows 用 `.zip` 而不是 `.tar.xz`，因为 Windows 自带的 `tar.exe` 不保证
能解 xz。

x86-64 版本用的是上游 SSE2 优化的 BLAMKA 轮函数 (`src/opt.c`)，按基线指令集
编译，所以在任何 x86-64 CPU 上都能跑。aarch64 版本用可移植的参考实现
(`src/ref.c`) —— 上游没有 NEON 优化路径。

## 构建

构建只在 CI 里发生，本地不需要配置任何东西。想手工复现某个目标，只需要
`zig` 和 `make`：

```sh
TARGET=linux-x64-musl sh scripts/build.sh     # -> build/linux-x64-musl/bin/argon2
TARGET=linux-x64-musl sh scripts/smoke.sh     # 格式校验 + 上游 KAT 向量
TARGET=linux-x64-musl sh scripts/package.sh   # -> dist/argon2-linux-x64-musl.tar.xz
```

整张目标表都在 `scripts/build.sh` 里，构建本身调用的是上游自带的 `Makefile`。
逐个编译选项的理由见 [`build-review.md`](build-review.md)。

## 来源

`upstream/argon2/` 下的源码是上游 commit [`f57e61e`][pin] 的逐字副本，没有
任何修改。上游的完整镜像（所有分支和 tag）在
[`x-cmd-sourcecode/argon2`](https://github.com/x-cmd-sourcecode/argon2)。

## 许可证

- 本仓库的封装部分（脚本、workflow、文档）：BSD-3-Clause，见 `LICENSE`
- Argon2 本身：CC0-1.0 OR Apache-2.0，见 `NOTICE.md`

[upstream]: https://github.com/p-h-c/phc-winner-argon2
[phc]: https://www.password-hashing.net/
[releases]: https://github.com/x-cmd-build/argon2/releases
[runs]: https://github.com/x-cmd-build/argon2/actions/workflows/build-and-test.yml
[pin]: https://github.com/p-h-c/phc-winner-argon2/commit/f57e61e19229e23c4445b85494dbf7c07de721cb
