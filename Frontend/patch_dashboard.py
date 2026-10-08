import re
import os

path = r'C:\RideAndServe\Frontend\lib\screens\driver\driver_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Make it Stateful
content = content.replace('class DriverDashboardScreen extends StatelessWidget', 'class DriverDashboardScreen extends StatefulWidget')

state_class = '''
  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  String? currentProfilePic;
  String currentDriverName = "";

  @override
  void initState() {
    super.initState();
    currentProfilePic = widget.profilePic;
    currentDriverName = widget.driverName;
  }

  void _updateProfileData() async {
    // Optionally fetch from backend
  }

  void _showActionFeedback(BuildContext context, String title) {
'''
content = content.replace('''  void _showActionFeedback(BuildContext context, String title) {''', state_class)

# Replace profilePic and driverName references
content = content.replace('profilePic!', 'currentProfilePic!')
content = content.replace('profilePic != null', 'currentProfilePic != null')
content = content.replace('driverName.', 'currentDriverName.')
content = content.replace('driverId', 'widget.driverId')
content = content.replace('token', 'widget.token')
content = content.replace('driverName:', 'driverName: currentDriverName,')
content = content.replace('profilePic:', 'profilePic: currentProfilePic,')

# Wait for ProfileSettingsScreen to return and if so, fetch or update
push_code = '''
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProfileSettingsScreen(
                                  driverName: currentDriverName,
                                  profilePic: currentProfilePic,
                                  driverId: widget.driverId,
                                  token: widget.token,
                                ),
                              ),
                            ).then((value) {
                                // Reload profile from server
                                if (widget.driverId != null && widget.token != null) {
                                    import_http();
                                }
                            });
'''
# Actually I'll just do it in Dart.

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
