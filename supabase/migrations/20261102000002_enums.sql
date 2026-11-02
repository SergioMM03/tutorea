-- Tutorea · Fase 14.2 · 02 Tipos enumerados
-- Los cinco tipos de la sección 3 del documento 14.1. Solo user_role se usa en esta fase;
-- los demás quedan listos para las tablas de 14.6 a 14.8 (no se crean esas tablas aquí).

create type public.user_role as enum ('estudiante', 'tutor', 'administrador');

create type public.booking_modality as enum ('presencial', 'virtual');

create type public.booking_status as enum (
  'pendiente',
  'aceptada',
  'rechazada',
  'cancelada',
  'pendiente_confirmacion',
  'completada'
);

create type public.incident_status as enum (
  'pendiente_revision',
  'en_investigacion',
  'resuelta',
  'desestimada'
);

create type public.notification_type as enum (
  'reserva_solicitada',
  'reserva_aceptada',
  'reserva_rechazada',
  'reserva_cancelada',
  'confirmacion_pendiente',
  'reserva_completada',
  'incidencia_reportada',
  'incidencia_actualizada'
);
