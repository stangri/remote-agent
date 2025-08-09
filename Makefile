include $(TOPDIR)/rules.mk

PKG_NAME:=remote-agent
PKG_RELEASE:=1
PKG_LICENSE:=BSD-2-Clause

include $(INCLUDE_DIR)/package.mk

define Package/remote-agent
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Remote agent for provisioning via rpcd (config/DHCP114/discoverable)
  DEPENDS:=+rpcd +uhttpd-mod-ubus +libubox +jsonfilter +openssl-util +curl +umdns
endef

define Package/remote-agent/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,remote-agent))
