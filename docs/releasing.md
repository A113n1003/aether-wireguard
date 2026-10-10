# 发布指南

首版和当前 tag 自动发布流程均标记为 pre-release。稳定版需要完成真实网络验收、签名和分发准备后再调整策略。

## 准备版本

1. 在 `VERSION` 设置目标版本，如 `0.1.0`。
2. 更新 `CHANGELOG.md` 和 `docs/release-notes-v<版本>.md`。
3. 检查 README、安装要求、数据与安全边界，移除私人配置和截图。
4. 本地运行 `./Scripts/release.sh`；完整 Xcode 下还运行 `swift test`。
5. 确认 CI 通过后，建立与 `VERSION` 一致的 tag。

```bash
git tag -a v0.1.0 -m 'Aether v0.1.0 development preview'
git push origin v0.1.0
```

GitHub Actions 会重新执行检查与构建，并发布 Apple Silicon zip 和 `SHA256SUMS`。tag 与 `VERSION` 不一致会失败。只授予发布 job 所需的 `contents: write`；CI 为只读。

## 手动发布或恢复失败的上传

tag 已在 GitHub 且已经检查目标 commit 后，可以上传本机生成的资产：

```bash
gh release create v0.1.0 \
  dist/Aether-v0.1.0-macos-arm64.zip dist/SHA256SUMS \
  --repo A113n1003/aether-wireguard --verify-tag --prerelease \
  --title 'Aether v0.1.0 — 开发预发布' \
  --notes-file docs/release-notes-v0.1.0.md
```

若 Release 已存在，先检查来源 commit 和已有文件；仅补传缺失资产。不要把另一份构建悄悄覆盖到同一个 Release。已经公开的 tag 不应 force push。

## 发布验收

- tag 指向预期 commit，版本号和 release note 一致。
- 检查脚本、完整 app 编译与 `codesign --verify --deep --strict` 通过。
- `Info.plist`、Mach-O 架构、zip 清单与 SHA-256 校验正确。
- 从 GitHub 下载 Release 资产后再次校验 SHA-256。
- 发布说明明确 ad hoc 签名、依赖、已验证行为与网络验证缺口。

当前签名不提供 Developer ID 来源认证；SHA-256 用于发现下载损坏，不替代签名或公证。
