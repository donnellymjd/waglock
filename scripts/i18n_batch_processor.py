#!/usr/bin/env python3
"""
批量国际化处理脚本
自动将硬编码的中文字符串替换为 String(localized:) 调用
"""

import re
import os
from pathlib import Path

# 字符串映射表 - 中文到英文键的映射
STRING_MAPPINGS = {
    # Videos
    "视频": "videos.title",
    "还没有视频": "videos.empty.title",
    "点击右上角 + 按钮导入视频": "videos.empty.subtitle",

    # Files
    "文件": "files.title",
    "还没有文件": "files.empty.title",
    "点击右上角 + 按钮导入文件": "files.empty.subtitle",

    # Settings
    "设置": "settings.title",
    "退出登录": "settings.logout.title",
    "退出后需要重新输入密码才能访问私密内容": "settings.logout.message",
    "清理缓存": "settings.clearCache.title",
    "组织管理": "settings.organization",
    "文件夹管理": "settings.folderManagement",
    "标签管理": "settings.tagManagement",
    "使用文件夹和标签来组织您的私密文件": "settings.organization.footer",
    "调整照片网格的列数和排序方式": "settings.display.footer",
    "计算中...": "settings.calculating",
    "清理缓存可释放临时文件占用的空间，不会删除您的私密文件": "settings.storage.footer",
    "修改密码": "settings.changePassword",
    "新密码至少 6 个字符": "settings.passwordRequirement",
    "重要提醒": "settings.importantReminder",
    "修改密码将使用新密码重新加密所有文件，这个过程可能需要较长时间，请保持应用打开直到完成。": "settings.changePassword.warning",
    "正在修改密码...": "settings.changingPassword",
    "确认修改": "settings.confirmChange",
    "零网络空间": "settings.appName",
    "版本 1.0.0": "settings.version",
    "零上传 · 零追踪 · 零风险": "settings.tagline",
    "真正的离线私密空间": "settings.subtitle",

    # Network Verification
    "零网络验证": "network.verification.title",
    "技术层面证明：完全离线，绝不联网": "network.verification.subtitle",
    "权限验证": "network.tab.permissions",
    "技术证明": "network.tab.technical",
    "数据流向": "network.tab.dataFlow",
    "应用权限检查": "network.permissions.title",
    "仅此一项权限！": "network.permissions.onlyOne",
    "技术实现证明": "network.technical.title",
    "所有加密操作均在设备本地完成，密钥从不离开设备": "network.technical.encryption",
    "所有文件加密后存储在应用私有目录，其他应用无法访问": "network.technical.storage",
    "代码级保证：没有网络能力 = 无法泄露数据": "network.technical.guarantee",
    "数据流向透明化": "network.dataFlow.title",
    "整个过程完全在您的设备上，无任何网络传输": "network.dataFlow.local",
    "解密后的数据仅存在于内存，退出应用后自动清除": "network.dataFlow.memory",
    "传统应用": "network.comparison.traditional",

    # Media
    "确定要删除此媒体吗？此操作无法撤销。": "media.delete.confirmation",
    "正在解密...": "media.decrypting",
    "加载失败": "media.loadFailed",
    "全屏播放": "media.fullscreen",
    "正在准备文档预览...": "media.preparing",
    "原文": "media.readMode.original",
    "文章模式": "media.readMode.article",
    "目录": "media.toc",

    # Common
    "取消": "common.cancel",
    "确定": "common.ok",
    "确认": "common.confirm",
    "删除": "common.delete",

    # Secret Space
    "隐藏空间": "secretSpace.title",

    # Export
    "批量导出": "export.title",
    "全选": "export.selectAll",
    "取消全选": "export.deselectAll",
    "导出选中项": "export.selected",

    # Import
    "从相册导入": "import.fromPhotos",
    "从文件导入": "import.fromFiles",
}

def replace_hardcoded_strings(file_path):
    """替换文件中的硬编码字符串"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        original_content = content
        changes_made = 0

        # 按字符串长度降序排序，避免短字符串误匹配长字符串的一部分
        sorted_mappings = sorted(STRING_MAPPINGS.items(), key=lambda x: len(x[0]), reverse=True)

        for chinese_str, key in sorted_mappings:
            # 匹配 Text("中文字符串") 或 Label("中文字符串", ...)
            # 但跳过已经使用 String(localized:) 的
            pattern = rf'(Text|Label)\("({re.escape(chinese_str)})"'
            replacement = rf'\1(String(localized: "{key}")'

            if re.search(pattern, content):
                content = re.sub(pattern, replacement, content)
                changes_made += 1
                print(f"  ✓ 替换: {chinese_str[:20]}... -> {key}")

        if changes_made > 0:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"✅ {file_path.name}: 完成 {changes_made} 处替换")
            return True
        else:
            print(f"⚪ {file_path.name}: 无需修改")
            return False

    except Exception as e:
        print(f"❌ {file_path.name}: 错误 - {e}")
        return False

def main():
    """主函数"""
    base_path = Path("/Users/WangQiao/Desktop/github/ios-dev/WagLock/WagLock/WagLock/Views")

    if not base_path.exists():
        print(f"❌ 路径不存在: {base_path}")
        return

    swift_files = list(base_path.rglob("*.swift"))
    print(f"\n🔍 找到 {len(swift_files)} 个 Swift 文件\n")

    modified_count = 0
    for swift_file in swift_files:
        if replace_hardcoded_strings(swift_file):
            modified_count += 1

    print(f"\n✨ 完成！共修改 {modified_count} 个文件")

if __name__ == "__main__":
    main()
