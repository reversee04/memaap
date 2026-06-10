import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screen for storing the patient's medical history locally.
/// Data is persisted in SharedPreferences and attached to emergency requests
/// so responders can see critical medical context.
class MedicalProfileScreen extends StatefulWidget {
  const MedicalProfileScreen({super.key});

  @override
  State<MedicalProfileScreen> createState() => _MedicalProfileScreenState();
}

class _MedicalProfileScreenState extends State<MedicalProfileScreen> {
  static const String _prefKey = 'medical_profile_json';

  bool _isLoading = true;
  bool _isSaving = false;

  String? _selectedBloodType;
  final List<String> _conditions = [];
  final List<String> _allergies = [];
  final List<String> _medications = [];

  final _conditionCtrl = TextEditingController();
  final _allergyCtrl = TextEditingController();
  final _medicationCtrl = TextEditingController();

  static const List<String> _bloodTypes = [
    'A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−', 'Unknown',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _conditionCtrl.dispose();
    _allergyCtrl.dispose();
    _medicationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null && json.isNotEmpty) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        setState(() {
          _selectedBloodType = data['bloodType'] as String?;
          _conditions
            ..clear()
            ..addAll((data['conditions'] as List? ?? []).cast<String>());
          _allergies
            ..clear()
            ..addAll((data['allergies'] as List? ?? []).cast<String>());
          _medications
            ..clear()
            ..addAll((data['medications'] as List? ?? []).cast<String>());
        });
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        if (_selectedBloodType != null) 'bloodType': _selectedBloodType,
        if (_conditions.isNotEmpty) 'conditions': _conditions,
        if (_allergies.isNotEmpty) 'allergies': _allergies,
        if (_medications.isNotEmpty) 'medications': _medications,
      };
      await prefs.setString(_prefKey, jsonEncode(data));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medical profile saved'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save profile'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  void _addItem(List<String> list, TextEditingController ctrl) {
    final value = ctrl.text.trim();
    if (value.isEmpty || list.contains(value)) return;
    setState(() => list.add(value));
    ctrl.clear();
  }

  void _removeItem(List<String> list, String item) {
    setState(() => list.remove(item));
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _buildChipList(
    List<String> items,
    Color color,
    TextEditingController ctrl,
    String hint,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: items
                .map(
                  (item) => Chip(
                    label: Text(item, style: const TextStyle(fontSize: 13)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => _removeItem(items, item),
                    backgroundColor: color.withOpacity(0.1),
                    deleteIconColor: color,
                    side: BorderSide(color: color.withOpacity(0.3)),
                  ),
                )
                .toList(),
          ),
        if (items.isNotEmpty) const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                onSubmitted: (_) => _addItem(items, ctrl),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _addItem(items, ctrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Medical Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue[50]!,
                          Colors.indigo[50]!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.info,
                          color: Colors.blue[700],
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This information is shown to medical responders when they accept your emergency request.',
                            style: TextStyle(
                              color: Colors.blue[800],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Blood Type
                  _buildSectionCard(
                    title: 'Blood Type',
                    icon: LucideIcons.droplets,
                    color: const Color(0xFFD32F2F),
                    child: DropdownButtonFormField<String>(
                      value: _selectedBloodType,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        hintText: 'Select blood type',
                      ),
                      items: _bloodTypes
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(t),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedBloodType = v),
                    ),
                  ),

                  // Medical Conditions
                  _buildSectionCard(
                    title: 'Medical Conditions',
                    icon: LucideIcons.heartPulse,
                    color: const Color(0xFFE53935),
                    child: _buildChipList(
                      _conditions,
                      const Color(0xFFE53935),
                      _conditionCtrl,
                      'e.g. Diabetes, Hypertension…',
                    ),
                  ),

                  // Allergies
                  _buildSectionCard(
                    title: 'Allergies',
                    icon: LucideIcons.alertTriangle,
                    color: const Color(0xFFF57C00),
                    child: _buildChipList(
                      _allergies,
                      const Color(0xFFF57C00),
                      _allergyCtrl,
                      'e.g. Penicillin, Peanuts…',
                    ),
                  ),

                  // Current Medications
                  _buildSectionCard(
                    title: 'Current Medications',
                    icon: LucideIcons.pill,
                    color: const Color(0xFF1976D2),
                    child: _buildChipList(
                      _medications,
                      const Color(0xFF1976D2),
                      _medicationCtrl,
                      'e.g. Aspirin 81mg, Metformin…',
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.save),
                      label: Text(
                        _isSaving ? 'Saving…' : 'Save Medical Profile',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0033CC),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
