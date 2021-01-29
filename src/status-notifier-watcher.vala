/**
   Copyright 2021 Andrzej Pacanowski <Andrzej.Pacanowski@gmail.com>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
 */

 /**
  * Debugging: dbus-monitor "interface='org.kde.StatusNotifierWatcher'" --session
  */

const string BUS_NAME = "org.kde.StatusNotifierWatcher";
const string BUS_OBJECT = "/StatusNotifierWatcher";

/**
 * Helper that keeps track of dbus objects.
 */
public class DbusServiceWatcher : Object {
    public delegate void AppearedCallback ();

    public delegate void VanishedCallback ();

    HashTable<string, uint> mapping = new HashTable<string, uint>(str_hash, str_equal);

    public void add_watch (string service, owned AppearedCallback appeared_callback, owned VanishedCallback vanished_callback)
    requires (!this.mapping.contains (service))
    {
        var id = Bus.watch_name (
            BusType.SESSION,
            service,
            BusNameWatcherFlags.NONE,
            (_, name) => {
            debug ("DbusServiceWatcher: Appeared %s", name);
            appeared_callback ();
        },
            (_, name) => {
            var id = this.mapping.take (name);
            debug ("DbusServiceWatcher: Vanished %s. Unwatching: %u ", name, id);
            this.mapping.remove (name);
            Bus.unwatch_name (id);
            vanished_callback ();
        });

        debug ("DbusServiceWatcher: Adding %s with id %u", service, id);
        this.mapping.insert (service, id);
    }
}

/**
 * Simple method that turns container into string[]
 */
string[] iterable_to_array (GenericSet<string> container) {
    string[] x = new string[container.length];
    uint idx = 0;
    container.foreach (e => {
        x[idx] = e;
        ++idx;
    });
    return x;
}

/* 
 * Main class that represents the DBus object StatusNotifierWatcher.
 * It registers and keeps track of all elements that want to display tray.
 * DBus interface definition:
 *   https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/StatusNotifierWatcher/
 */
[DBus (name = "org.kde.StatusNotifierWatcher")]
public class StatusNotifierWatcher : Object {
    private DbusServiceWatcher dbus_service_watcher = new DbusServiceWatcher ();

    private GenericSet<string> _RegisteredStatusNotifierItems = new GenericSet<string>(str_hash, str_equal);
    /**
     * DBus property with all registered services.
     */
    public string[] RegisteredStatusNotifierItems { owned get {
                                                        return iterable_to_array (_RegisteredStatusNotifierItems);
                                                    } }
    
    /**
    * DBus property with information if we have a "display" counterpart connected.
    * This is what DesktopEnvironment will provide.
    * TODO: for no we fake it always to true.
    */
    public bool IsStatusNotifierHostRegistered { get; default = true; }

    /**
     * DBus property with version of the protocol.
     * TODO: work on getting that specified in freedesktop.org
     */
    public int32 ProtocolVersion { get; default = 0; }

    /**
     * DBus method that HAVE TO be called by any piece of SW that wants to display in a tray.
     */
    public void RegisterStatusNotifierItem (string service, GLib.BusName sender) {
        message ("Received RegisterStatusNotifierItem %s sender=%s", service, sender);

        string real_service;
        string bus_service_name;
        _ayatana_hack(service, sender, out real_service, out bus_service_name);

        dbus_service_watcher.add_watch (
            real_service,
            () => { _RegisteredStatusNotifierItems.add (bus_service_name); StatusNotifierItemRegistered (bus_service_name); },
            () => { _RegisteredStatusNotifierItems.remove (bus_service_name); StatusNotifierItemUnregistered (bus_service_name); }
        );
    }

    /**
     * In freedesktop spec what we get as @param registered_service should be out @param service but
     * in case of Ayatana we get not a dbus service path but an dbus object path!
     *  eg. /org/ayatana/NotificationItem/some_app_name
     * instead of
     *  eg. org.kde.StatusNotifierItem-2650-1
     * This cannot be used to watch bus so we need to register on @param sender which is something like :1.136.
     * This also requires a hack for output name of the service @param bus_service_name:
     *  eg. :1.136/org/ayatana/NotificationItem/some_app_name
     * Unfortunately this means that users of this application will need to follow the hack :(
     */
    private void _ayatana_hack(string registered_service, string sender, out string service, out string bus_service_name) {
        if (registered_service[0] == '/') {
            var ayatana = "/org/ayatana/NotificationItem";
            if (registered_service[0 : ayatana.length] == ayatana) {
                warning ("Ayatana NotificationItem found : %s with sender %s", registered_service, sender);
                service = sender;
                bus_service_name = sender + registered_service;
            } else {
                // TODO: this will crash for the time of development of this feature.
                error ("Not implemented for " + registered_service);
            }
        } else if (registered_service[0] == ':') {
            if (registered_service == sender) {
                // unnamed-sender eg. telegram
                warning ("Unnamed NotificationItem found : %s with sender %s. This is not according to spec but we workaround it.", registered_service, sender);
                service = sender;
                bus_service_name = sender + "/StatusNotifierItem";
            } else {
                warning("Service %s from sender %s is not valid for us. Please report it.", registered_service, sender);
                service = "";
                bus_service_name = "";
            }
        } else {
            service = registered_service;
            bus_service_name = registered_service;
        }
    }

    /**
     * DBus method that shoud be called by DesktopEnvironment that  want's to implement tray.
     * In Gnome3 that would be gnome-shell extension.
     * TODO: implement this. For now we fake we always have one registered
     */
    public void RegisterStatusNotifierHost (string service) throws Error {
        message ("RegisterStatusNotifierHost %s", service);
    }

    /**
     * DBus signals. Self explanatory.
     */
    public signal void StatusNotifierItemRegistered (string service);
    public signal void StatusNotifierItemUnregistered (string service);
    public signal void StatusNotifierHostRegistered ();

    // TODO: no unregistered in freedesktop spec
    //  public signal void StatusNotifierHostUnregistered ();
}

void main () {
    var loop = new MainLoop ();
    Bus.own_name (
        BusType.SESSION,
        BUS_NAME,
        BusNameOwnerFlags.NONE,
        (conn) => {
            try {
                conn.register_object (BUS_OBJECT, new StatusNotifierWatcher ());
            } catch (IOError e) {
                error ("Could not register service");
            }
        },
        () => debug ("Acquired %s name on the bus.", BUS_NAME),
        () => error ("Could not aquire %s name on the bus.", BUS_NAME)
    );
    loop.run ();
}
