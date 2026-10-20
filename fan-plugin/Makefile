include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ps5-fan
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-ps5-fan
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=PS5 automatic fan control and manual maximum mode
  DEPENDS:=+libc +luci-base +rpcd +jshn +jsonfilter
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) ./src/ps5_control.c $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) $(TARGET_LDFLAGS) -Wall -Wextra -o $(PKG_BUILD_DIR)/ps5_control $(PKG_BUILD_DIR)/ps5_control.c
endef

define Package/luci-app-ps5-fan/conffiles
/etc/config/ps5_fan
endef

define Package/luci-app-ps5-fan/install
	$(CP) ./files/* $(1)/
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ps5_control $(1)/usr/sbin/ps5_control
	chmod 755 $(1)/etc/init.d/ps5-fan $(1)/usr/libexec/ps5-fanctl $(1)/usr/libexec/rpcd/ps5.fan
endef

$(eval $(call BuildPackage,luci-app-ps5-fan))
