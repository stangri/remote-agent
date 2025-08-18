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
  DEPENDS:=+rpcd +uhttpd +uhttpd-mod-ucode +libubox +jsonfilter +openssl-util +curl +umdns
endef

define Package/remote-agent/conffiles
/etc/config/remote-agent
/etc/remote-agent/uuid
/etc/remote-agent/password_hash
endef

define Package/remote-agent/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/remote-agent $(1)/etc/config/remote-agent
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/remote-agent-enroll $(1)/etc/init.d/remote-agent-enroll
	$(SED) "s|^\(readonly PKG_VERSION\).*|\1='$(PKG_VERSION)-r$(PKG_RELEASE)'|" $(1)/etc/init.d/remote-agent-enroll
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/99-remote-agent $(1)/etc/uci-defaults/99-remote-agent
	$(INSTALL_DIR) $(1)/usr/share/ucode/remote-agent
	$(INSTALL_DATA) ./files/usr/share/ucode/remote-agent/adopt.uc $(1)/usr/share/ucode/remote-agent/adopt.uc
	$(INSTALL_DIR) $(1)/usr/lib/remote-agent
	$(INSTALL_BIN) ./usr/lib/remote-agent/functions.sh $(1)/usr/lib/remote-agent/functions.sh
	$(INSTALL_DIR) $(1)/usr/libexec/remote-agent
	$(INSTALL_BIN) ./usr/libexec/remote-agent/enroll-runner $(1)/usr/libexec/remote-agent/enroll-runner
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd/remote-agent
	$(INSTALL_BIN) ./usr/libexec/rpcd/remote-agent $(1)/usr/libexec/rpcd/remote-agent
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd/remote-agent.d
	$(INSTALL_DATA) ./usr/libexec/rpcd/remote-agent.d/.keep $(1)/usr/libexec/rpcd/remote-agent.d/.keep
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./usr/share/rpcd/acl.d/remote-agent.json $(1)/usr/share/rpcd/acl.d/remote-agent.json
	$(INSTALL_DIR) $(1)/usr/share/udhcpc/defaults.script.d
	$(INSTALL_BIN) ./usr/share/udhcpc/defaults.script.d/50-remote-agent $(1)/usr/share/udhcpc/defaults.script.d/50-remote-agent
endef

$(eval $(call BuildPackage,remote-agent))
