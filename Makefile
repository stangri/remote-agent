# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright 2017-2025 MOSSDeF, Stan Grishin (stangri@melmac.ca).

include $(TOPDIR)/rules.mk

PKG_NAME:=remote-agent
PKG_VERSION:=0.0.1
PKG_RELEASE:=1
PKG_LICENSE:=AGPL-3.0-or-later
PKG_MAINTAINER:=Stan Grishin <stangri@melmac.ca>

include $(INCLUDE_DIR)/package.mk

define Package/remote-agent
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Remote agent for OpenWrt provisioning via rpcd (config/DHCP114/discoverable)
  DEPENDS:=+rpcd +uhttpd-mod-ubus +libubox +jsonfilter +openssl-util +curl +umdns
endef

define Package/remote-agent/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/remote-agent $(1)/etc/config/remote-agent
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/remote-agent-enroll $(1)/etc/init.d/remote-agent-enroll
	$(SED) "s|^\(readonly PKG_VERSION\).*|\1='$(PKG_VERSION)-r$(PKG_RELEASE)'|" $(1)/etc/init.d/remote-agent-enroll
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN)  ./files/etc/uci-defaults/99-remote-agent $(1)/etc/uci-defaults/99-remote-agent
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd/remote-agent
	$(INSTALL_DATA) ./usr/libexec/rpcd/remote-agent $(1)/usr/libexec/rpcd/remote-agent
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd/remote-agent.d
	$(INSTALL_DATA) ./usr/libexec/rpcd/remote-agent.d/.keep $(1)/usr/libexec/rpcd/remote-agent.d/.keep
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./usr/share/rpcd/acl.d/remote-agent.json $(1)/usr/share/rpcd/acl.d/remote-agent.json
	$(INSTALL_DIR) $(1)/usr/share/udhcpc/defaults.script.d
	$(INSTALL_DATA) ./usr/share/udhcpc/defaults.script.d/50-remote-agent $(1)/usr/share/udhcpc/defaults.script.d/50-remote-agent
endef

$(eval $(call BuildPackage,remote-agent))
