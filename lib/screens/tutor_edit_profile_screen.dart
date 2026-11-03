import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../state/session_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../utils/id_generator.dart';
import '../widgets/app_back_button.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_title.dart';
import '../widgets/subject_chip.dart';
import '../widgets/tutor_avatar.dart';

/// Crear o editar el perfil del tutor con TutorStore.saveProfile().
/// La disponibilidad se edita por día: cada AvailabilitySlot conserva su
/// propio horario (ej. lunes 8–12 y miércoles 2–6).
/// La fotografía es opcional: se elige de la galería, se guarda una copia
/// permanente y sin ella se muestran las iniciales.
class TutorEditProfileScreen extends StatefulWidget {
  const TutorEditProfileScreen({super.key});

  @override
  State<TutorEditProfileScreen> createState() => _TutorEditProfileScreenState();
}

class _TutorEditProfileScreenState extends State<TutorEditProfileScreen> {
  /// Horas que se pueden elegir (minutos desde medianoche): 6:00 AM – 10:00 PM.
  static final List<int> _hours = [for (var h = 6; h <= 22; h++) h * 60];

  final _description = TextEditingController();
  final _price = TextEditingController();
  final Set<String> _subjects = {};

  /// Un borrador por AvailabilitySlot (se editan y guardan uno a uno).
  final List<_SlotDraft> _slots = [];
  int _nextSlotKey = 0;

  /// Horario con el que se activa un día nuevo: 8:00 AM – 8:00 PM.
  static const int _defaultFrom = 8 * 60;
  static const int _defaultTo = 20 * 60;
  bool _active = true;
  bool _inPerson = true;
  bool _virtual = true;
  bool _saving = false;
  String? _validation;

  TutorProfile? _original;

  /// Id del perfil (el existente, o uno nuevo al crearlo).
  late final String _profileId;

  /// Fotografía mostrada en el formulario (null = iniciales).
  String? _photoPath;

  /// Copias de fotografías hechas en esta pantalla. Las que no se guarden
  /// se borran al salir, para no dejar archivos sin usar.
  final Set<String> _newPhotoCopies = {};
  bool _picking = false;
  bool _saved = false;
  late final TutorStore _tutors;

  @override
  void initState() {
    super.initState();
    final tutors = context.read<TutorStore>();
    _tutors = tutors;
    final profile = tutors.myProfile;
    _original = profile;
    _profileId = profile?.id ?? IdGenerator.newId('tp');
    _photoPath = profile?.photoPath;
    if (profile != null) {
      _description.text = profile.descripcion;
      _price.text = profile.precioHora == profile.precioHora.roundToDouble()
          ? profile.precioHora.toStringAsFixed(0)
          : profile.precioHora.toString();
      _subjects.addAll(profile.materias);
      for (final slot in profile.disponibilidad) {
        _slots.add(_SlotDraft(_nextSlotKey++, slot.diaSemana, slot.horaInicio, slot.horaFin));
      }
      _active = profile.activo;
      _inPerson = profile.ofrecePresencial;
      _virtual = profile.ofreceVirtual;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tutors.clearError();
    });
  }

  @override
  void dispose() {
    // Salió sin guardar: las copias nuevas no las usa ningún perfil.
    if (!_saved) {
      for (final path in _newPhotoCopies) {
        _tutors.deletePhotoFile(path);
      }
    }
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  // ---------------- Fotografía ----------------

  Future<void> _pickPhoto() async {
    if (_picking) return; // evita abrir la galería dos veces
    setState(() => _picking = true);
    final path = await _tutors.pickProfilePhoto(_profileId);
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (path != null) {
        _newPhotoCopies.add(path);
        _photoPath = path; // vista previa
      }
    });
  }

  void _removePhoto() => setState(() => _photoPath = null);

  /// Devuelve el primer problema del formulario, o null.
  String? _validate(double? price) {
    if (_description.text.trim().isEmpty) return 'Escribe una descripción.';
    if (price == null || price <= 0) return 'Escribe un precio por hora válido.';
    if (_subjects.isEmpty) return 'Elige al menos una materia.';
    if (!_inPerson && !_virtual) return 'Elige al menos una modalidad: presencial o virtual.';
    if (_slots.isEmpty) return 'Elige al menos un día disponible.';
    for (final s in _slots) {
      if (s.from >= s.to) {
        return '${Formatters.weekdayShortOf(s.day)}: la hora de inicio debe ser '
            'antes de la hora de fin.';
      }
    }
    for (final a in _slots) {
      for (final b in _slots) {
        if (a.key < b.key && a.day == b.day && a.from < b.to && b.from < a.to) {
          return '${Formatters.weekdayShortOf(a.day)}: hay horarios que se cruzan.';
        }
      }
    }
    return null;
  }

  /// Días que tienen al menos un horario.
  Set<int> get _days => {for (final s in _slots) s.day};

  /// Activa un día (con el horario por defecto) o lo quita con sus horarios.
  void _toggleDay(int day) => setState(() {
        if (_days.contains(day)) {
          _slots.removeWhere((s) => s.day == day);
        } else {
          _slots.add(_SlotDraft(_nextSlotKey++, day, _defaultFrom, _defaultTo));
        }
      });

  /// Horarios ordenados por día y hora (para mostrarlos y guardarlos).
  List<_SlotDraft> get _sortedSlots => [..._slots]
    ..sort((a, b) => a.day != b.day ? a.day.compareTo(b.day) : a.from.compareTo(b.from));

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final user = context.read<SessionStore>().user;
    final tutors = context.read<TutorStore>();
    if (user == null) return;

    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    final problem = _validate(price);
    setState(() => _validation = problem);
    if (problem != null) return;

    final slots = [
      for (final s in _sortedSlots)
        AvailabilitySlot(diaSemana: s.day, horaInicio: s.from, horaFin: s.to),
    ];
    final profile = _original?.copyWith(
          descripcion: _description.text.trim(),
          precioHora: price,
          materias: _subjects.toList(),
          disponibilidad: slots,
          activo: _active,
          photoPath: _photoPath,
          removePhoto: _photoPath == null,
          ofrecePresencial: _inPerson,
          ofreceVirtual: _virtual,
        ) ??
        TutorProfile(
          id: _profileId,
          userId: user.id,
          universityId: user.universityId,
          descripcion: _description.text.trim(),
          precioHora: price!,
          materias: _subjects.toList(),
          disponibilidad: slots,
          activo: _active,
          photoPath: _photoPath,
          ofrecePresencial: _inPerson,
          ofreceVirtual: _virtual,
        );

    setState(() => _saving = true);
    final ok = await tutors.saveProfile(profile);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return; // el error del store se muestra arriba

    // Guardado: se borran la foto anterior (si se reemplazó o eliminó)
    // y las copias que se descartaron en esta pantalla.
    _saved = true;
    final previous = _original?.photoPath;
    if (previous != null && previous != _photoPath) tutors.deletePhotoFile(previous);
    for (final path in _newPhotoCopies) {
      if (path != _photoPath) tutors.deletePhotoFile(path);
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Perfil guardado')));
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tutors = context.watch<TutorStore>();
    final universityId = context.watch<SessionStore>().user?.universityId;
    final catalog = tutors.subjects.where((s) => s.universityId == universityId).toList();
    final error = _validation ?? tutors.error;

    return Scaffold(
      appBar: AppBar(
        title: Text(_original == null ? 'Crear perfil' : 'Editar perfil'),
        leading: const AppBackButton(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              if (error != null) ...[
                FormErrorBanner(message: error),
                const SizedBox(height: AppSpacing.md),
              ],
              const SectionTitle(title: 'Fotografía de perfil'),
              const SizedBox(height: AppSpacing.sm),
              _PhotoSection(
                name: context.watch<SessionStore>().user?.nombre ?? '',
                photoPath: _photoPath,
                enabled: tutors.canPickPhotos && !_picking,
                onPick: _pickPhoto,
                onRemove: _photoPath == null ? null : _removePhoto,
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Sobre mí'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Cuéntales a los estudiantes cómo enseñas.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Precio por hora'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Precio (USD)', prefixText: '\$ '),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Materias que ofrezco'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final s in catalog)
                    SubjectChip(
                      label: s.nombre,
                      selected: _subjects.contains(s.id),
                      onTap: () => setState(() {
                        if (!_subjects.remove(s.id)) _subjects.add(s.id);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Disponibilidad'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (var d = 1; d <= 7; d++)
                    SubjectChip(
                      label: Formatters.weekdayShortOf(d),
                      selected: _days.contains(d),
                      onTap: () => _toggleDay(d),
                    ),
                ],
              ),
              // Un renglón por horario: cada día conserva el suyo.
              for (final slot in _sortedSlots) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  key: ValueKey('slot-${slot.key}'),
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(Formatters.weekdayShortOf(slot.day),
                          style: textTheme.titleMedium),
                    ),
                    Expanded(
                      child: _HourField(
                        label: 'Desde',
                        value: slot.from,
                        hours: _hours,
                        onChanged: (v) => setState(() => slot.from = v),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _HourField(
                        label: 'Hasta',
                        value: slot.to,
                        hours: _hours,
                        onChanged: (v) => setState(() => slot.to = v),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              // Fase 14.7: modalidades del tutor (al menos una).
              SwitchListTile(
                key: const Key('modality-in-person'),
                contentPadding: EdgeInsets.zero,
                title: Text('Tutorías presenciales', style: textTheme.titleMedium),
                value: _inPerson,
                onChanged: (v) => setState(() => _inPerson = v),
              ),
              SwitchListTile(
                key: const Key('modality-virtual'),
                contentPadding: EdgeInsets.zero,
                title: Text('Tutorías virtuales', style: textTheme.titleMedium),
                value: _virtual,
                onChanged: (v) => setState(() => _virtual = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Visible para estudiantes', style: textTheme.titleMedium),
                subtitle: const Text('Si lo apagas, no apareces en las búsquedas.'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: PrimaryButton(
          label: 'Guardar perfil',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ),
    );
  }
}

/// Vista previa de la fotografía (o iniciales) con sus acciones.
class _PhotoSection extends StatelessWidget {
  final String name;
  final String? photoPath;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  const _PhotoSection({
    required this.name,
    required this.photoPath,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  /// Ancho del avatar en la sección.
  static const double _avatarSize = 88;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasPhoto = photoPath != null;
    final label = hasPhoto ? 'Cambiar fotografía' : 'Seleccionar fotografía';

    // Botón a todo el ancho disponible. OutlinedButton.icon envuelve la
    // etiqueta en un Flexible: si no cabe en una línea, pasa a dos líneas
    // en lugar de desbordarse (antes: "RenderFlex overflowed by 37 pixels").
    // Mismo estilo que SecondaryButton (outlinedButtonTheme).
    final pickButton = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('pick-photo'),
        onPressed: enabled ? onPick : null,
        icon: const Icon(Icons.photo_library_outlined, size: 20),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );

    final actions = <Widget>[
      pickButton,
      if (onRemove != null)
        TextButton.icon(
          key: const Key('remove-photo'),
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Eliminar fotografía'),
        ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Opcional. Sin fotografía se muestran tus iniciales.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Espacio que necesita el botón en una sola línea (crece con el
        // tamaño de texto del sistema): ícono + relleno + ~15 caracteres.
        final buttonNeeds = 76 + MediaQuery.textScalerOf(context).scale(16) * 15;
        final besideAvatar = constraints.maxWidth - _avatarSize - AppSpacing.md;

        // Pantallas angostas (ej. teléfonos): avatar arriba y botón debajo.
        if (besideAvatar < buttonNeeds) {
          return Column(
            key: const Key('photo-section-stacked'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TutorAvatar(name: name, photoPath: photoPath, size: _avatarSize),
              const SizedBox(height: AppSpacing.md),
              ...actions,
            ],
          );
        }

        // Pantallas anchas: avatar a la izquierda y acciones a la derecha.
        return Row(
          key: const Key('photo-section-row'),
          children: [
            TutorAvatar(name: name, photoPath: photoPath, size: _avatarSize),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: actions,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Horario de un día mientras se edita (se convierte en AvailabilitySlot al guardar).
class _SlotDraft {
  final int key; // identifica el renglón aunque cambie el orden
  final int day;
  int from;
  int to;

  _SlotDraft(this.key, this.day, this.from, this.to);
}

/// Selector de hora (8:00 AM, 9:00 AM...).
class _HourField extends StatelessWidget {
  final String label;
  final int value;
  final List<int> hours;
  final ValueChanged<int> onChanged;

  const _HourField({
    required this.label,
    required this.value,
    required this.hours,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Si el valor guardado no está en la lista (ej. 8:30), se agrega.
    final options = {...hours, value}.toList()..sort();
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final h in options)
          DropdownMenuItem(value: h, child: Text(Formatters.time(h))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
