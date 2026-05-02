import 'package:flutter/material.dart';
import '../services/db_service.dart';

const Map<String, Color> _riskColors = {
  'LOW': Color(0xFF1DB85A),
  'MODERATE': Color(0xFFF5A623),
  'HIGH': Color(0xFFD0021B),
  'CRITICAL': Color(0xFF7B0000),
};

class ResultScreen extends StatelessWidget {
  final Map<String, dynamic> result;

  const ResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final riskLevel = result['risk_level'] ?? 'MODERATE';
    final riskScore = result['risk_score'] ?? 50;
    final color = _riskColors[riskLevel] ?? Colors.grey;

    return Scaffold(
      appBar: AppBar(title: const Text('Analysis Result')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Risk banner
            Container(
              color: color,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    riskLevel,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (riskLevel == 'CRITICAL')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'DO NOT DISPENSE',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Risk score circle
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: riskScore / 100,
                          strokeWidth: 6,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                        Text(
                          '$riskScore',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Extracted fields
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Extracted Information',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _buildField('Medicine', result['medicine_name']),
                      _buildField('Batch Code', result['batch_code']),
                      _buildField('Expiry Date', result['expiry_date']),
                      _buildField(
                        'Manufacturer',
                        result['manufacturer'] != null
                            ? result['manufacturer']['extracted']
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Flags
            if ((result['flags'] as List?)?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: (result['flags'] as List)
                      .cast<String>()
                      .map((flag) => Chip(label: Text(flag)))
                      .toList(),
                ),
              ),
            // Analysis notes
            if (result['analysis_notes'] != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Analysis Notes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(result['analysis_notes'] ?? ''),
                      ],
                    ),
                  ),
                ),
              ),
            // Buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.camera),
                    label: const Text('Scan Another'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _saveToHistory(context),
                    icon: const Icon(Icons.save),
                    label: const Text('Save to History'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value?.toString() ?? 'Unknown')),
        ],
      ),
    );
  }

  Future<void> _saveToHistory(BuildContext context) async {
    try {
      final scanId = DateTime.now().millisecondsSinceEpoch.toString();
      await DbService.saveScan(
        id: scanId,
        timestamp: DateTime.now().toIso8601String(),
        location: result['location'],
        medicineName: result['medicine_name'],
        batchCode: result['batch_code'],
        expiryDate: result['expiry_date'],
        riskScore: result['risk_score'] ?? 50,
        riskLevel: result['risk_level'] ?? 'MODERATE',
        flags: List<String>.from(result['flags'] ?? []),
        fullResult: result,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to history')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
