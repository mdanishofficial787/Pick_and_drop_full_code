import 'package:flutter/material.dart';
import 'package:ride_and_serve/screens/customer/homescreen.dart';
import 'package:ride_and_serve/screens/driver/driver_auth_landing_screen.dart';

enum AccountType { customer, driver }

class AccountTypeScreen extends StatefulWidget {
  const AccountTypeScreen({super.key});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  AccountType _selectedAccount = AccountType.customer;

  void _continue() {
    if (_selectedAccount == AccountType.customer) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const Homescreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const DriverAuthLandingScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FE),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 30),

            child: Column(
              children: [
                const SizedBox(height: 85),

                // =================================================
                // LOGO
                // =================================================
                SizedBox(
                  width: 250,
                  height: 150,

                  child: Image.asset(
                    'assets/images/rns_logo.png',

                    fit: BoxFit.contain,

                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.directions_car,
                        size: 130,
                        color: Color(0xFF102A52),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // =================================================
                // TAGLINE
                // =================================================
                const Text(
                  'Ride, Serve, Connect.',

                  textAlign: TextAlign.center,

                  style: TextStyle(
                    fontSize: 39,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF096CFA),
                  ),
                ),

                const SizedBox(height: 80),

                // =================================================
                // WELCOME
                // =================================================
                const Text(
                  'Welcome!',

                  style: TextStyle(
                    fontSize: 47,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF171A1F),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Choose your account type to continue',

                  textAlign: TextAlign.center,

                  style: TextStyle(fontSize: 27, color: Color(0xFF454D62)),
                ),

                const SizedBox(height: 90),

                // =================================================
                // CUSTOMER + DRIVER
                // =================================================
                Row(
                  children: [
                    Expanded(
                      child: _AccountCard(
                        title: 'Customer',

                        icon: Icons.groups_outlined,

                        selected: _selectedAccount == AccountType.customer,

                        onTap: () {
                          setState(() {
                            _selectedAccount = AccountType.customer;
                          });
                        },
                      ),
                    ),

                    const SizedBox(width: 28),

                    Expanded(
                      child: _AccountCard(
                        title: 'Driver',

                        icon: Icons.person_outline,

                        selected: _selectedAccount == AccountType.driver,

                        onTap: () {
                          setState(() {
                            _selectedAccount = AccountType.driver;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 100),

                // =================================================
                // CONTINUE BUTTON
                // =================================================
                SizedBox(
                  width: double.infinity,
                  height: 116,

                  child: ElevatedButton(
                    onPressed: _continue,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0878F9),

                      foregroundColor: Colors.white,

                      elevation: 5,

                      shadowColor: Colors.black26,

                      shape: const StadiumBorder(),
                    ),

                    child: const Text(
                      'CONTINUE',

                      style: TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 60),

                // =================================================
                // TERMS
                // =================================================
                Wrap(
                  alignment: WrapAlignment.center,

                  children: [
                    const Text(
                      'By continuing, you agree to our ',

                      style: TextStyle(fontSize: 21, color: Color(0xFF4A5362)),
                    ),

                    GestureDetector(
                      onTap: () {},

                      child: const Text(
                        'Terms',

                        style: TextStyle(
                          fontSize: 21,
                          color: Color(0xFF0878F9),
                        ),
                      ),
                    ),

                    const Text(
                      ' & ',

                      style: TextStyle(fontSize: 21, color: Color(0xFF4A5362)),
                    ),

                    GestureDetector(
                      onTap: () {},

                      child: const Text(
                        'Privacy Policy',

                        style: TextStyle(
                          fontSize: 21,
                          color: Color(0xFF0878F9),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// ACCOUNT CARD
// =============================================================

class _AccountCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AccountCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),

        height: 380,

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(30),

          border: Border.all(
            color: selected ? const Color(0xFF0878F9) : Colors.transparent,

            width: selected ? 4 : 0,
          ),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),

              blurRadius: 12,

              offset: const Offset(0, 6),
            ),
          ],
        ),

        child: Stack(
          children: [
            // ===================================================
            // ICON + TITLE
            // ===================================================
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  Container(
                    width: 150,
                    height: 150,

                    decoration: const BoxDecoration(
                      color: Color(0xFFE7F0FC),
                      shape: BoxShape.circle,
                    ),

                    child: Icon(
                      icon,

                      size: 82,

                      color: selected
                          ? const Color(0xFF0878F9)
                          : const Color(0xFF7A828C),
                    ),
                  ),

                  const SizedBox(height: 58),

                  Text(
                    title,

                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF171A1F),
                    ),
                  ),
                ],
              ),
            ),

            // ===================================================
            // CHECK MARK
            // ===================================================
            if (selected)
              Positioned(
                top: 22,
                right: 22,

                child: Container(
                  width: 50,
                  height: 50,

                  decoration: const BoxDecoration(
                    color: Color(0xFF0878F9),
                    shape: BoxShape.circle,
                  ),

                  child: const Icon(Icons.check, color: Colors.white, size: 30),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
