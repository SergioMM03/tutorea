import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import '../routes/app_navigator.dart';
import '../state/booking_store.dart';
import '../state/session_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../utils/tutorea_time.dart';
import '../widgets/app_back_button.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/subject_chip.dart';
import '../widgets/tutor_avatar.dart';

/// 5. Reserva de tutoría (MVP).
/// Recibe el [TutorSummary] y crea un Booking real con BookingStore.createRequest().
class BookingScreen extends StatefulWidget {
  final TutorSummary tutor;
  const BookingScreen({super.key, required this.tutor});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  /// Días que se ofrecen: los próximos 5 a partir de mañana.
  static const int _daysShown = 5;

  /// Horas de inicio posibles (minutos desde medianoche): 8:00 AM … 6:00 PM.
  static const List<int> _startTimes = [480, 600, 720, 840, 960, 1080];

  /// Duraciones en minutos.
  static const List<int> _durations = [60, 90, 120];

  late final List<DateTime> _dates;
  Subject? _subject;
  DateTime? _date;
  int? _startMinutes;
  int _duration = 60;
  TutoringModality? _modality;
  final _topic = TextEditingController();
  final _location = TextEditingController();

  /// Modalidades que ofrece el tutor, en orden fijo.
  List<TutoringModality> get _modalities =>
      [for (final m in TutoringModality.values) if (_profile.ofrece(m)) m];

  TutorProfile get _profile => widget.tutor.profile;

  @override
  void initState() {
    super.initState();
    // Fechas y horas en hora de El Salvador (TutoreaTime).
    final today = DateUtils.dateOnly(TutoreaTime.now());
    _dates = [for (var i = 1; i <= _daysShown; i++) today.add(Duration(days: i))];

    _subject = widget.tutor.subjects.isEmpty ? null : widget.tutor.subjects.first;
    _modality = _modalities.firstOrNull;
    _date = _dates.where(_dayAvailable).firstOrNull;
    _startMinutes = _date == null ? null : _timesFor(_date!).firstOrNull;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BookingStore>().clearError();
    });
  }

  @override
  void dispose() {
    _topic.dispose();
    _location.dispose();
    super.dispose();
  }

  // ---------------- Disponibilidad ----------------

  DateTime _at(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

  /// Horas en que el tutor atiende ese día con la duración elegida.
  List<int> _timesFor(DateTime day) => [
        for (final t in _startTimes)
          if (_profile.disponibleEn(_at(day, t), _duration)) t,
      ];

  bool _dayAvailable(DateTime day) => _timesFor(day).isNotEmpty;

  void _selectDate(DateTime day) => setState(() {
        _date = day;
        if (!_timesFor(day).contains(_startMinutes)) {
          _startMinutes = _timesFor(day).firstOrNull;
        }
      });

  void _selectDuration(int minutes) => setState(() {
        _duration = minutes;
        // Si la hora elegida ya no cabe con la nueva duración, se quita.
        if (_date != null && !_timesFor(_date!).contains(_startMinutes)) {
          _startMinutes = null;
        }
      });

  // ---------------- Enviar ----------------

  /// Devuelve el primer problema encontrado, o null si todo está bien.
  String? _validate(SessionStore session) {
    final user = session.user;
    if (user == null) return 'Inicia sesión para solicitar una tutoría.';
    if (_profile.userId == user.id) return selfBookingMessage;
    if (!_profile.activo) return 'Este tutor no está disponible por ahora.';
    if (_subject == null) return 'Elige una materia.';
    if (!_profile.ensenaMateria(_subject!.id)) return 'El tutor no imparte esa materia.';
    if (_modality == null || !_profile.ofrece(_modality!)) {
      return 'Elige una modalidad que el tutor ofrezca.';
    }
    if (_date == null) return 'Elige una fecha.';
    if (_startMinutes == null) return 'Elige una hora.';
    if (!_durations.contains(_duration)) return 'Elige una duración válida.';
    final start = _at(_date!, _startMinutes!);
    if (!start.isAfter(TutoreaTime.now())) return 'Elige una fecha y hora futuras.';
    if (!_profile.disponibleEn(start, _duration)) {
      return 'El tutor no atiende en ese horario.';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final session = context.read<SessionStore>();
    final bookings = context.read<BookingStore>();

    final problem = _validate(session);
    if (problem != null) {
      bookings.reportError(problem);
      return;
    }

    final created = await bookings.createRequest(
      studentId: session.user!.id,
      tutorId: widget.tutor.id,
      subjectId: _subject!.id,
      tema: _topic.text.trim().isEmpty ? null : _topic.text.trim(),
      fechaHora: _at(_date!, _startMinutes!),
      duracion: _duration,
      modalidad: _modality,
      ubicacion: _location.text.trim().isEmpty ? null : _location.text.trim(),
    );
    if (!mounted || created == null) return; // el error del store se muestra arriba

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitud enviada correctamente')),
    );
    AppNavigator.toMyBookings(context);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final bookingStore = context.watch<BookingStore>();
    final tutor = widget.tutor;
    final times = _date == null ? const <int>[] : _timesFor(_date!);

    return Scaffold(
      appBar: AppBar(title: const Text('Reservar sesión'), leading: const AppBackButton()),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              AppSpacing.lg,
            ),
            children: [
              const _FieldLabel('Materia'),
              DropdownButtonFormField<Subject>(
                initialValue: _subject,
                isExpanded: true,
                borderRadius: BorderRadius.circular(AppRadius.md),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textPrimary),
                items: [
                  for (final s in tutor.subjects)
                    DropdownMenuItem(value: s, child: Text(s.nombre)),
                ],
                onChanged: (s) => setState(() => _subject = s),
              ),
              const SizedBox(height: AppSpacing.md),
              const _FieldLabel('Tema específico', suffix: ' (opcional)'),
              TextField(
                controller: _topic,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ej. Distribuciones de probabilidad',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _FieldLabel('Modalidad'),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final m in _modalities)
                    SubjectChip(
                      label: m.label,
                      selected: _modality == m,
                      onTap: () => setState(() => _modality = m),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _FieldLabel(_modality == TutoringModality.virtual ? 'Enlace de la reunión' : 'Lugar',
                  suffix: ' (opcional)'),
              TextField(
                key: const Key('booking-location'),
                controller: _location,
                maxLength: 300,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: _modality == TutoringModality.virtual
                      ? 'Ej. enlace de Meet o Zoom'
                      : 'Ej. Biblioteca, segundo piso',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _FieldLabel('Fecha'),
              _DateSelector(
                dates: _dates,
                selected: _date,
                isEnabled: _dayAvailable,
                onSelected: _selectDate,
              ),
              const SizedBox(height: AppSpacing.md),
              const _FieldLabel('Hora'),
              if (_date == null)
                const _Hint('Este tutor no tiene horarios disponibles en los próximos días.')
              else if (times.isEmpty)
                const _Hint('No hay horarios para esa duración. Prueba una más corta.')
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final t in times)
                      SubjectChip(
                        label: Formatters.time(t),
                        selected: _startMinutes == t,
                        onTap: () => setState(() => _startMinutes = t),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              const _FieldLabel('Duración'),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final d in _durations)
                    SubjectChip(
                      label: Formatters.durationMinutes(d),
                      selected: _duration == d,
                      onTap: () => _selectDuration(d),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const _FieldLabel('Resumen'),
              _BookingSummary(
                tutor: tutor,
                subject: _subject,
                date: _date,
                startMinutes: _startMinutes,
                duration: _duration,
              ),
              if (bookingStore.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                FormErrorBanner(message: bookingStore.error!),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: PrimaryButton(
          label: 'Enviar solicitud',
          loading: bookingStore.isLoading,
          onPressed: _submit,
        ),
      ),
    );
  }
}

/// Etiqueta de campo: "Materia", "Tema específico (opcional)"...
class _FieldLabel extends StatelessWidget {
  final String text;
  final String? suffix;
  const _FieldLabel(this.text, {this.suffix});

  @override
  Widget build(BuildContext context) {
    // Mismo estilo que SectionTitle (titleLarge) para que todos los títulos coincidan.
    final style = Theme.of(context).textTheme.titleLarge;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text.rich(
        TextSpan(
          text: text,
          style: style,
          children: [
            if (suffix != null)
              TextSpan(text: suffix, style: style?.copyWith(fontWeight: FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

/// Texto de ayuda gris.
class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textSecondary),
      );
}

/// Fila de 5 fechas. Las que el tutor no atiende se ven grises y no se pueden elegir.
class _DateSelector extends StatelessWidget {
  final List<DateTime> dates;
  final DateTime? selected;
  final bool Function(DateTime) isEnabled;
  final ValueChanged<DateTime> onSelected;

  const _DateSelector({
    required this.dates,
    required this.selected,
    required this.isEnabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < dates.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _DateTile(
              date: dates[i],
              selected: selected == dates[i],
              enabled: isEnabled(dates[i]),
              onTap: () => onSelected(dates[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _DateTile({
    required this.date,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final background = selected
        ? AppColors.primary
        : enabled
            ? AppColors.primarySoft
            : AppColors.disabled;
    final foreground = selected
        ? AppColors.textOnPrimary
        : enabled
            ? AppColors.textPrimary
            : AppColors.textSecondary;
    final radius = BorderRadius.circular(AppRadius.md);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: Material(
        color: background,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm + AppSpacing.xs,
              horizontal: AppSpacing.xs,
            ),
            // FittedBox: en pantallas angostas o con texto grande,
            // el contenido se reduce en vez de desbordarse.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                children: [
                  Text(Formatters.weekdayShort(date),
                      style: textTheme.bodyLarge?.copyWith(color: foreground)),
                  Text('${date.day}',
                      style: textTheme.titleLarge?.copyWith(color: foreground)),
                  Text(Formatters.monthShort(date),
                      style: textTheme.bodyLarge?.copyWith(color: foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resumen: tutor, materia, precio por hora, fecha, horario y total.
class _BookingSummary extends StatelessWidget {
  final TutorSummary tutor;
  final Subject? subject;
  final DateTime? date;
  final int? startMinutes;
  final int duration;

  const _BookingSummary({
    required this.tutor,
    required this.subject,
    required this.date,
    required this.startMinutes,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final timeRange = startMinutes == null
        ? 'Elige una hora'
        : '${Formatters.time(startMinutes!)} – ${Formatters.time(startMinutes! + duration)}';
    final total = Booking.calcularPrecio(tutor.precioHora, duration);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TutorAvatar(name: tutor.nombre, photoPath: tutor.profile.photoPath, size: 72),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tutor.nombre, style: textTheme.titleMedium),
                    Text(subject?.nombre ?? 'Elige una materia', style: textTheme.bodyLarge),
                    Text(Formatters.pricePerHour(tutor.precioHora),
                        style: textTheme.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(date == null ? 'Elige una fecha' : Formatters.dateLong(date!),
                        style: textTheme.bodyLarge),
                    Text(timeRange, style: textTheme.bodyLarge),
                  ],
                ),
              ),
              Text('Total: ${Formatters.price(total)}', style: textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}
