project('status-notifier-watcher', 'vala', 'c')

dependencies = [
    dependency('gio-2.0')
]
sources = files('src/status-notifier-watcher.vala')
executable('status-notifier-watcher', sources, dependencies: dependencies, install : true)

install_data(['extra/status-notifier-watcher.service'], install_dir : '/etc/systemd/user')
