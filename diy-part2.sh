#!/bin/bash
#
# immortalwrt-Actions DIY part 2 (After Update feeds)
#
# 默认 LAN IP（如需改网关地址，取消下一行注释）
#sed -i 's/192.168.1.1/192.168.1.1/g' package/base-files/files/bin/config_generate

# 主机名
sed -i 's/ImmortalWrt/ImmortalWrt/g' package/base-files/files/bin/config_generate

# 确保旧版 luasrc 插件兼容层启用（tcpdump 界面需要）
grep -q CONFIG_PACKAGE_luci-compat .config || echo 'CONFIG_PACKAGE_luci-compat=y' >> .config
exit 0
