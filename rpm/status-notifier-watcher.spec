# https://docs.fedoraproject.org/en-US/packaging-guidelines/Meson/

Name: status-notifier-watcher-service
Version: 0.0.1
Release: 1%{?dist}
Summary: StatusNotifierWatcher implementation for tray support
License: ASL 2.0
URL: https://www.github.com/p4cu/status-notifier-watcher-service/
BuildArch: noarch

Source0: %{name}-%{version}.tar.gz

BuildRequires: meson
BuildRequires: gcc
BuildRequires: vala
BuildRequires: pkgconfig(gio-2.0)
BuildRequires: systemd-rpm-macros

%description
Implementation of StatusNotifierWatcher as a systemd service.
See specification for StatusNotifierWatcher on freedesktop.org 
This requires a DesktopEnvironment counterpart.
Eg. for gnome-shell it will be some sort of extension.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install

%check
%meson_test

%files
/etc/systemd/user/status-notifier-watcher.service
/usr/bin/status-notifier-watcher

%changelog
* Thu Jan 28 2021 Andrzej Pacanowski <Andrzej.Pacanowski@gmail.com> - 
- initial

%post
%systemd_user_post status-notifier-watcher.service
