#!/usr/bin/env python3
"""
Replace hardcoded Chinese strings with String(localized:) calls
"""

import os
import re

# Precise mapping of Chinese strings to localization keys
STRING_MAPPINGS = {
    # Export
    "批量导出": "export.title",
    "取消全选": "export.deselectAll",
    "全选": "export.selectAll",
    "导出": "common.export",
    "导出失败": "export.failed",
    "清空": "export.clear",
    "正在导出...": "export.inProgress",
    "正在解密并准备文件，请稍候...": "export.decrypting",
    "没有可导出的文件": "export.empty.title",
    "请先导入一些文件": "export.empty.subtitle",
    "正在准备分享...": "export.preparingShare",
    "无法获取密码,请重新登录": "export.error.noPassword",
    # Folders
    "文件夹": "folders.title",
    "选择文件夹": "folders.select.title",
    "选择目标文件夹": "folders.selectTarget.title",
    "新建文件夹": "folders.new.title",
    "编辑文件夹": "folders.edit.title",
    "所有媒体（移除文件夹）": "folders.allMedia.remove",
    "所有媒体（默认）": "folders.allMedia.default",
    "所有媒体": "folders.allMedia",
    "系统文件夹": "folders.system",
    "自定义文件夹": "folders.custom",
    "文件夹名称": "folders.name.placeholder",
    "选择图标": "folders.selectIcon",
    "选择颜色": "folders.selectColor",
    "基本信息": "folders.basicInfo",
    "预览": "folders.preview",
    "文件夹是空的": "folders.empty.title",
    "将媒体文件移动到此文件夹": "folders.empty.subtitle",
    # Tags
    "选择标签": "tags.select.title",
    "还没有标签": "tags.empty",
    "创建新标签": "tags.create.title",
    "标签名称": "tags.name.placeholder",
    "输入新标签的名称": "tags.inputPrompt",
    "添加标签": "tags.add.title",
    "标签": "tags.title",
    # Disguise
    "伪装模式": "disguise.title",
    "启用伪装模式": "disguise.enable.title",
    "伪装计算器": "disguise.calculator.title",
    "启用后，应用启动时将显示计算器界面而非登录界面": "disguise.enable.description",
    "密码序列": "disguise.passwordSequence",
    "使用默认密码": "disguise.useDefault",
    "已设置": "disguise.isSet",
    "解锁密码": "disguise.unlockPassword",
    "使用说明": "disguise.instructions.title",
    "在计算器中输入此数字序列后按 = 号即可解锁应用": "disguise.instructions.howTo",
    "示例: 输入 1234.56 再按 =": "disguise.instructions.example",
    "⚠️ 当前使用默认密码 1234，建议设置自定义密码": "disguise.warning.defaultPassword",
    "计算器完全可用，可进行正常计算": "disguise.tip.calculator",
    "密码序列仅支持数字和小数点": "disguise.tip.numbersOnly",
    "密码序列不会显示在计算结果中": "disguise.tip.noDisplay",
    "密码错误时不会有任何提示（伪装特性）": "disguise.tip.noFeedback",
    "伪装模式安全提示": "disguise.security.title",
    "• 计算器界面完全真实，无法被识破\\n• 不会保留任何计算历史记录\\n• 请牢记您的密码序列": "disguise.security.tips",
    "需要修改主密码": "disguise.changePassword.required.title",
    "伪装模式要求主密码仅包含数字和小数点。\\n\\n当前主密码包含字母或特殊字符，请修改为仅包含数字和小数点的密码。": "disguise.changePassword.required.message",
    "修改密码": "disguise.changePassword.action",
    "密码序列设置": "disguise.passwordSetup.title",
    "⚠️ 当前主密码包含字母或特殊字符": "disguise.passwordSetup.warning",
    "请设置一个仅包含数字和小数点的新密码": "disguise.passwordSetup.instruction1",
    "修改后，需要重新导入文件（旧文件将无法解密）": "disguise.passwordSetup.instruction2",
    "当前主密码符合伪装模式要求": "disguise.passwordSetup.compatible",
    "可以直接使用，或设置为其他数字密码": "disguise.passwordSetup.canUse",
    "仅支持数字 (0-9) 和小数点 (.)": "disguise.passwordSetup.rule1",
    "建议使用 4-8 位数字": "disguise.passwordSetup.rule2",
    "简单数字": "disguise.example.simple",
    "连续数字": "disguise.example.sequential",
    "带小数点": "disguise.example.decimal",
    "日期数字": "disguise.example.date",
    "示例密码": "disguise.example.title",
    "设置密码序列": "disguise.setPassword.title",
    "确认修改密码": "disguise.confirmChange.title",
    "继续修改": "disguise.confirmChange.continue",
    "修改主密码后，下次登录需要使用新密码。\\n\\n加密文件会继续使用最初设置的密钥，无需等待重新加密。": "disguise.confirmChange.message",
    "正在更新密码...": "disguise.updating",
    "密码仅能包含数字和小数点": "disguise.error.numbersOnly",
    "密码至少需要4位": "disguise.error.minLength",
    "无法获取当前密码，请重新登录": "disguise.error.noPassword",
    "输入密码序列": "disguise.input.placeholder",
    # Files
    "文件": "files.title",
    "搜索文件": "files.search.placeholder",
    "开始导入": "files.import.start",
    # File Preview
    "正在导出...": "filePreview.exporting",
    "正在解密文件...": "filePreview.decrypting",
    "提示": "filePreview.alert.title",
    "PDF 预览": "filePreview.pdf.title",
    "点击分享按钮导出查看": "filePreview.pdf.instruction",
    "正在加载...": "filePreview.loading",
    "无法显示此文本文件": "filePreview.text.error",
    "暂不支持预览此文件类型": "filePreview.unsupported",
    "导出文件": "filePreview.export",
    "无法获取密码，请重新登录后再试。": "filePreview.error.noPassword",
    "操作失败，请稍后重试。": "filePreview.error.generic",
    "关闭": "common.close",
    # Gallery
    "零网络空间": "gallery.title",
    "搜索文件名或扩展名": "gallery.search.placeholder",
    "删除媒体": "gallery.delete.title",
    "还没有媒体文件": "gallery.empty.title",
    "点击右上角 + 按钮导入照片、视频或文件": "gallery.empty.subtitle",
    "移动": "gallery.move",
    "移动到文件夹": "gallery.moveToFolder",
    # Import
    "导入媒体": "import.title",
    "导入失败": "import.failed",
    "保存到文件夹": "import.saveToFolder",
    "选择导入方式": "import.selectMethod.title",
    "导入的文件将被自动加密保护": "import.selectMethod.subtitle",
    "从相册导入": "import.fromPhotos.title",
    "选择照片和视频": "import.fromPhotos.subtitle",
    "从文件导入": "import.fromFiles.title",
    "选择任意文件": "import.fromFiles.subtitle",
    "停止导入": "import.stop",
    "支持的格式：": "import.formats.title",
    "• 照片: JPG, PNG, HEIC, GIF 等": "import.formats.photos",
    "• 视频: MP4, MOV, M4V 等": "import.formats.videos",
    "• 文档: PDF, DOC, TXT 等所有类型": "import.formats.documents",
    "导入成功！": "import.success.title",
    "提示：如果您从 iCloud Drive 或其他云盘中选择「仅保存在云端」的文件，iOS 系统会为下载该文件短暂使用网络，并可能弹出「是否允许使用无线数据」提示。这属于系统为帮您下载云端文件触发的网络行为，本应用自身不会主动发起任何网络请求。": "import.cloudNotice",
    # Loading
    "加载中...": "common.loading",
    "正在处理...": "common.processing",
    "正在导入图片": "common.importing.photos",
    # Media Detail
    "无法解析为文本内容。": "media.text.parseError",
    "无法获取密码": "media.error.noPassword",
    "第": "media.page.prefix",
    "章": "media.chapter",
    "节": "media.section",
    "回": "media.chapter.alt",
    "正在生成文章模式…": "media.article.generating",
    "无法从此 PDF 中提取文本内容。": "media.pdf.extractFailed",
    "目录": "media.toc.title",
    "搜索": "common.search",
    # Network Verification
    "验证方式": "network.verification.method",
    "四个「零」承诺": "network.promises.title",
    "零网络": "network.promise.zero.network",
    "代码中无任何网络请求，无网络权限": "network.promise.zero.network.desc",
    "零上传": "network.promise.zero.upload",
    "所有数据仅保存本地，绝不上传云端": "network.promise.zero.upload.desc",
    "零追踪": "network.promise.zero.tracking",
    "无统计SDK，无广告SDK，无用户行为追踪": "network.promise.zero.tracking.desc",
    "零风险": "network.promise.zero.risk",
    "没有云端 = 没有泄露风险": "network.promise.zero.risk.desc",
    "✅ 已请求权限": "network.permissions.requested",
    "照片库访问": "network.permission.photos",
    "导入照片和视频到加密空间": "network.permission.photos.purpose",
    "❌ 明确不请求的权限": "network.permissions.notRequested",
    "网络访问": "network.permission.network",
    "完全不需要": "network.permission.notNeeded",
    "位置信息": "network.permission.location",
    "麦克风": "network.permission.microphone",
    "相机": "network.permission.camera",
    "蓝牙": "network.permission.bluetooth",
    "🔐 本地加密技术": "network.encryption.title",
    "加密算法": "network.encryption.algorithm",
    "密钥派生": "network.encryption.keyDerivation",
    "PBKDF2 (10万次迭代)": "network.encryption.pbkdf2",
    "哈希算法": "network.encryption.hash",
    "密钥存储": "network.encryption.keyStorage",
    "💾 数据存储方式": "network.storage.title",
    "存储位置": "network.storage.location",
    "应用沙盒 (本地)": "network.storage.sandbox",
    "数据库": "network.storage.database",
    "SwiftData (本地)": "network.storage.swiftdata",
    "文件加密": "network.storage.encryption",
    "是 (全部加密)": "network.storage.encryption.yes",
    "云端同步": "network.storage.cloudSync",
    "禁用 (iCloud关闭)": "network.storage.cloudSync.disabled",
    "📝 代码层面保证": "network.code.guarantees.title",
    "无任何URLSession网络请求代码": "network.code.noURLSession",
    "无第三方网络SDK集成": "network.code.noThirdPartySDK",
    "无统计分析SDK (如Google Analytics)": "network.code.noAnalytics",
    "无广告SDK": "network.code.noAds",
    "无云存储SDK (如AWS S3)": "network.code.noCloudStorage",
    "Info.plist中无网络权限声明": "network.code.noNetworkPermission",
    "【重要说明】如果您从 iCloud Drive、云盘等「仅在云端」的位置导入文件，iOS 系统会为下载该文件短暂使用网络，并可能弹出「是否允许使用无线数据」提示。这是系统为云端文件下载触发的网络行为，不是应用在主动联网，本应用自身没有任何网络请求代码。": "network.cloudImportNotice",
    "📥 数据导入流程": "network.dataFlow.import.title",
    "用户选择文件": "network.dataFlow.selectFile",
    "从相册选择照片/视频/文件": "network.dataFlow.selectFromPhotos",
    "离线验证": "network.offline.title",
    # Common
    "取消": "common.cancel",
    "确定": "common.ok",
    "确认": "common.confirm",
    "删除": "common.delete",
    "完成": "common.done",
    "保存": "common.save",
    "编辑": "common.edit",
    "创建": "common.create",
    "继续": "common.continue",
    "选择": "common.select",
    "分享": "common.share",
    "错误": "common.error",
}


def replace_in_file(file_path, dry_run=True):
    """Replace hardcoded Chinese strings in a Swift file"""
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    original_content = content
    replacements = []

    # Sort by length (longest first) to avoid partial replacements
    sorted_mappings = sorted(
        STRING_MAPPINGS.items(), key=lambda x: len(x[0]), reverse=True
    )

    for chinese_str, key in sorted_mappings:
        # Pattern: "chinese_string" not followed by String(localized:
        pattern = f'"{re.escape(chinese_str)}"'

        # Find all occurrences
        matches = list(re.finditer(pattern, content))

        for match in matches:
            # Check if already localized
            start_pos = match.start()
            context_before = content[max(0, start_pos - 50) : start_pos]

            if "String(localized:" in context_before:
                continue  # Already localized

            # Replace with String(localized: "key")
            new_str = f'String(localized: "{key}")'
            content = content[: match.start()] + new_str + content[match.end() :]

            replacements.append(
                {"old": chinese_str, "new": key, "position": match.start()}
            )

    if content != original_content:
        if not dry_run:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(content)
            print(
                f"✅ Updated: {os.path.basename(file_path)} ({len(replacements)} replacements)"
            )
        else:
            print(
                f"📝 Would update: {os.path.basename(file_path)} ({len(replacements)} replacements)"
            )
            for r in replacements[:5]:  # Show first 5
                print(f"   '{r['old']}' → '{r['new']}'")
            if len(replacements) > 5:
                print(f"   ... and {len(replacements) - 5} more")

        return len(replacements)

    return 0


def main():
    import sys

    dry_run = "--dry-run" in sys.argv or "-n" in sys.argv

    view_files = [
        "WagLock/Views/Export/BatchExportView.swift",
        "WagLock/Views/Folders/BatchFolderSelectionView.swift",
        "WagLock/Views/Tags/BatchTagSelectionView.swift",
        "WagLock/Views/Disguise/DisguiseSettingsView.swift",
        "WagLock/Views/Files/FilePreviewView.swift",
        "WagLock/Views/Files/FilesView.swift",
        "WagLock/Views/Folders/FolderListView.swift",
        "WagLock/Views/Folders/FolderSelectionView.swift",
        "WagLock/Views/Gallery/GalleryView.swift",
        "WagLock/Views/Import/ImportButtonsView.swift",
        "WagLock/Views/Components/LoadingOverlay.swift",
        "WagLock/Views/Gallery/MediaDetailView.swift",
        "WagLock/Views/Security/NetworkVerificationView.swift",
        "WagLock/Views/Tags/TagManagementView.swift",
    ]

    total_replacements = 0
    updated_files = 0

    print("=" * 60)
    if dry_run:
        print("DRY RUN MODE - No files will be modified")
        print("Run without --dry-run to apply changes")
    else:
        print("LIVE MODE - Files will be modified")
    print("=" * 60 + "\n")

    for file_path in view_files:
        if os.path.exists(file_path):
            count = replace_in_file(file_path, dry_run=dry_run)
            if count > 0:
                total_replacements += count
                updated_files += 1
        else:
            print(f"⚠️  File not found: {file_path}")

    print(f"\n{'=' * 60}")
    print(f"Summary:")
    print(f"  Files processed: {len(view_files)}")
    print(f"  Files with changes: {updated_files}")
    print(f"  Total replacements: {total_replacements}")
    print(f"{'=' * 60}")

    if dry_run:
        print("\n💡 Run without --dry-run to apply these changes")


if __name__ == "__main__":
    main()
