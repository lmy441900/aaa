using Gtk;
using Gee;

namespace Aaa {
  [GtkTemplate (ui = "/hk/edu/uic/aaa/ui/aaa-winmain.ui")]
  public class WinMain : ApplicationWindow, ChatUI {
    [GtkChild]
    private HeaderBar headerbar_main;
    [GtkChild]
    private Entry entry_welcome_user_id;
    [GtkChild]
    private Button btn_welcome_ignite;
    [GtkChild]
    private Stack stack_welcome;
    [GtkChild]
    private Label lbl_user_id;
    [GtkChild]
    private ListBox listbox_users;
    [GtkChild]
    private Button btn_user_add;
    [GtkChild]
    private Button btn_user_del;
    [GtkChild]
    private Stack stack_main;
    [GtkChild]
    private Box box_messages;
    [GtkChild]
    private TextView textview_tosend;

    private SocketService socket_service;
    private HashMap<string, Daemon> peers; // <id, daemon>

    public WinMain() {
      this.peers = new HashMap<string, Daemon>();
    }

    public SocketService get_socket_service() {
      return this.socket_service;
    }

    public void set_socket_service(SocketService socket_service) {
      this.socket_service = socket_service;
    }

    public void welcome() {
      this.stack_welcome.set_visible_child_name("stackpage_welcome");
    }

    public void chat() {
      this.lbl_user_id.set_text(config_get_id());
      this.stack_welcome.set_visible_child_name("stackpage_chat");
    }

    public void push_message(string id, string msg) {
      this.box_messages.add(new MsgRow(id, msg));
    }

    public void push_user(string id, string ip) {
      this.listbox_users.add(
        new ContactRow(
          ContactStatus.ONLINE,
          id,
          ip
        )
      );
    }

    public void remove_user(string? id, string? ip) {
      this.listbox_users.foreach((row) => {
        if (((row as ListBoxRow).get_child() as ContactRow).get_id() == id ||
            ((row as ListBoxRow).get_child() as ContactRow).get_addr() == ip) {
          (row as ListBoxRow).destroy();
          this.peers.unset(ip);
        }
      });
    }

    [GtkCallback]
    private void btn_welcome_ignite_clicked_cb() {
      // Create user key
      UserKey *key;
      int r = keypair_gen(out key);
      if (r == 0) {
        var dlg = new MessageDialog(
          this,
          DialogFlags.DESTROY_WITH_PARENT | DialogFlags.MODAL,
          MessageType.ERROR,
          ButtonsType.OK,
          "Failed to generate a key pair for you. This may because various reasons, but currently we cannot perform anything further.");
        dlg.run();
        return;
      }

      // Generate user config
      config_set_id(this.entry_welcome_user_id.get_text());
      config_set_cert(key.sign.public_key);
      config_set_key(key.sign.secret_key);
      config_save();

      // Make visual changes
      this.lbl_user_id.set_text(config_get_id());
      this.stack_welcome.set_visible_child_name("stackpage_chat");
    }

    [GtkCallback]
    private void btn_user_add_clicked_cb() {
      var dlg_add_contact = new DlgAddContact();
      int ret = dlg_add_contact.run();

      switch (ret) {
        case ResponseType.OK:
          dlg_add_contact.set_status("Connecting...");

          var daemon = this.socket_service.connect(dlg_add_contact.get_ip(), 1234); // XXX: Port
          if (daemon == null) {
            var dlg = new MessageDialog(dlg_add_contact,
                              DialogFlags.DESTROY_WITH_PARENT | DialogFlags.MODAL,
                              MessageType.ERROR,
                              ButtonsType.OK,
                              "Failed to connect to %s:%u", dlg_add_contact.get_ip(), 1234);
            dlg.run();
            break;
          }

          var remote_id = daemon.get_remote_id();
          var remote_ip = daemon.get_remote_ip();

          // Contact row is added by daemon
          this.peers.set(remote_id, (daemon.ref() as Daemon));

          break;
        case ResponseType.CANCEL: // fall through
        default:
          break;
      }

      dlg_add_contact.destroy();
    }

    [GtkCallback]
    private void btn_user_del_clicked_cb() {
      var selected_row = this.listbox_users.get_selected_row();
      if (selected_row != null) {
        // Disconnect with peer first
        var remote_id = (selected_row.get_child() as ContactRow).get_id();
        var remote_ip = (selected_row.get_child() as ContactRow).get_addr();
        var daemon = this.peers.get(remote_id);

        if (daemon != null) {
          debug("trying to disconnect from %s (%s)...", remote_id, remote_ip);
          try {
            daemon.bye(true); // Gracefully shut down the connection
          } catch (Error e) {
            message("failed to wave hand to the peer... let it go");
            daemon.disconnect(); // Forcefully shut down the connection
          }
        }

        // Contact row is removed by daemon

        message("connection to %s (%s) closed", remote_id, remote_ip);
      }
    }

    [GtkCallback]
    private void listbox_users_row_selected_cb(ListBoxRow? row) {
      if (row == null) {
        // Switch to the welcome page
        this.headerbar_main.set_title("Welcome");
        this.stack_main.set_visible_child_name("stackpage_welcome");
      } else {
        // Fill chat history
        // Show peer id as main title
        // Switch to the chat page
        // unimpl
        this.stack_main.set_visible_child_name("stackpage_messaging");
      }
    }

    [GtkCallback]
    private void btn_send_clicked_cb() {
      var buffer = this.textview_tosend.get_buffer();

      // We want the whole message so get an start iter and an end iter
      TextIter start, end;
      buffer.get_start_iter(out start);
      buffer.get_end_iter(out end);

      var text = buffer.get_text(start, end, false);

      // Clear the text view
      buffer.delete(ref start, ref end);

      // Don't send blank content
      if (text.length == 0)
        return;

      // Show message of current user on the window
      this.box_messages.add(new MsgRow("You", text));

      // Get current peer ID
      var remote_id = (this.listbox_users.get_selected_row().get_child() as ContactRow).get_id();

      // Send message
      var daemon = this.peers.get(remote_id);
      daemon.sendmsg(text);
    }
  }
}
