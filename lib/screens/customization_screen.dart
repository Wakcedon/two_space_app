import 'package:flutter/material.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/config/ui_tokens.dart';

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  late int _selectedColor;

  final List<Map<String, dynamic>> _choices = [
    {'name': 'Amethyst', 'value': 0xFF7C4DFF},
    {'name': 'Deep Purple', 'value': 0xFF6A1B9A},
    {'name': 'Violet', 'value': 0xFF8E24AA},
    {'name': 'Orchid', 'value': 0xFF9C27B0},
    {'name': 'Imperial', 'value': 0xFF5E35B1},
    {'name': 'Lilac', 'value': 0xFF7B1FA2},
    // New pale violet shade placed near Lilac
    {'name': 'Pale Violet', 'value': 0xFFE8D7FF},
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = SettingsService.themeNotifier.value.primaryColorValue;
  }

  // Available font choices. Note: fonts must exist on device or be bundled in pubspec.yaml to take effect.
  final List<String> _fontChoices = [
    'Inter',
    'Roboto',
    'Noto Sans',
    'Open Sans',
    'Oswald',
    'Press Start 2P',
    'Comic Sans MS',
  ];
  late String _selectedFont = SettingsService.themeNotifier.value.fontFamily;
  late int _selectedWeight = SettingsService.themeNotifier.value.fontWeight;

  FontWeight _resolveFontWeight(int w) {
    if (w >= 900) return FontWeight.w900;
    if (w >= 800) return FontWeight.w800;
    if (w >= 700) return FontWeight.w700;
    if (w >= 600) return FontWeight.w600;
    if (w >= 500) return FontWeight.w500;
    if (w >= 400) return FontWeight.w400;
    if (w >= 300) return FontWeight.w300;
    return FontWeight.w400;
  }

  Future<void> _select(int value) async {
    setState(() => _selectedColor = value);
    await SettingsService.setPrimaryColor(value);
    // If Pale Violet selected, enable the special light-mode flag; otherwise disable it
    if (value == 0xFFE8D7FF) {
      await SettingsService.setPaleVioletMode(true);
    } else {
      await SettingsService.setPaleVioletMode(false);
    }
  }

  Future<void> _setFont(String font) async {
    setState(() => _selectedFont = font);
    await SettingsService.setFont(font);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Кастомизация')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Выберите основной цвет приложения', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Column(
              children: _choices.map((item) {
                final v = item['value'] as int;
                final name = item['name'] as String;
                final selected = v == _selectedColor;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Material(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.cornerSm)),
                    color: selected ? Color(v) : Theme.of(context).colorScheme.surface,
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Color(v)),
                      title: Text(name, style: selected ? const TextStyle(color: Colors.white) : null),
                      trailing: selected ? const Icon(Icons.check, color: Colors.white) : null,
                      onTap: () => _select(v),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Шрифт приложения', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _fontChoices.map((f) {
                final sel = f == _selectedFont;
                // smaller preview size for Press Start 2P because it's large by design
                final previewSize = f == 'Press Start 2P' ? 12.0 : 16.0;
                return ChoiceChip(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  avatar: sel ? const Icon(Icons.check, size: 16) : null,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Aa', style: TextStyle(fontFamily: f, fontWeight: _resolveFontWeight(600), fontSize: previewSize)),
                      const SizedBox(width: 8),
                      Text(f, style: TextStyle(fontFamily: f, fontWeight: _resolveFontWeight(_selectedWeight), fontSize: previewSize)),
                    ],
                  ),
                  selected: sel,
                  onSelected: (_) {
                    _setFont(f);
                    setState(() => _selectedFont = f);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const Text('Толщина шрифта', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // Slider for font weight (300 - 900)
            StatefulBuilder(builder: (c, setLocal) {
              return Row(children: [
                Expanded(
                  child: Slider(
                    min: 300,
                    max: 900,
                    divisions: 6,
                    value: _selectedWeight.toDouble().clamp(300, 900),
                    label: '$_selectedWeight',
                    onChanged: (v) {
                      setLocal(() => _selectedWeight = v.round());
                      setState(() {});
                    },
                    onChangeEnd: (v) async {
                      await SettingsService.setFontWeight(v.round());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 48, child: Center(child: Text('$_selectedWeight'))),
              ]);
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
