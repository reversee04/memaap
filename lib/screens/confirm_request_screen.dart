import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/emergency_provider.dart';

class ConfirmRequestScreen extends StatelessWidget {
  const ConfirmRequestScreen({super.key});

  Widget _buildTypeCard(BuildContext context, String title, IconData icon, Color iconColor) {
    final provider = context.watch<EmergencyProvider>();
    bool isSelected = provider.selectedEmergencyType == title;
    
    return GestureDetector(
      onTap: () => context.read<EmergencyProvider>().setEmergencyType(title),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: Theme.of(context).colorScheme.primary),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.mapPin, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Malawi Medical SOS',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[200],
              child: Icon(LucideIcons.user, color: Colors.grey[600], size: 20),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Confirm Request',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Confirm your emergency details to dispatch help',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Map Placeholder with Pin
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.teal[800], // Darker map tone
                    borderRadius: BorderRadius.circular(20),
                    image: const DecorationImage(
                      image: NetworkImage('https://maps.googleapis.com/maps/api/staticmap?center=-13.9626,33.7741&zoom=15&size=600x300&maptype=satellite&key=NO_KEY'), // Fake map background
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.5,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                colors: [Colors.green.shade900, Colors.teal.shade700],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 40,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'LIVE LOCATION\nPIN SET',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Center(
                        child: Icon(
                          LucideIcons.mapPin,
                          color: Colors.blue,
                          size: 48,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Emergency Type Selector
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'SELECT EMERGENCY TYPE',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.5,
                  children: [
                    _buildTypeCard(context, 'Accident', LucideIcons.car, Colors.red),
                    _buildTypeCard(context, 'Illness', LucideIcons.plusSquare, Theme.of(context).colorScheme.primary),
                    _buildTypeCard(context, 'Maternal', LucideIcons.user, Theme.of(context).colorScheme.primary),
                    _buildTypeCard(context, 'Other', LucideIcons.moreHorizontal, Colors.grey),
                  ],
                ),
                const SizedBox(height: 100), // Space for sticky button
              ],
            ),
          ),
          
          // Sticky Confirm Button
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: provider.state == EmergencyState.loading
                    ? null
                    : () async {
                        // Call provider to trigger emergency
                        final success = await context.read<EmergencyProvider>().triggerEmergency(context);
                        if (success && context.mounted) {
                          context.go('/tracking');
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.read<EmergencyProvider>().errorMessage ?? 'Failed')),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: provider.state == EmergencyState.loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Confirm Request',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
