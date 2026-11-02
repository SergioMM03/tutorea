-- Tutorea · Fase 14.2 · 01 Extensiones
-- pgcrypto: gen_random_bytes y utilidades criptográficas (gen_random_uuid ya es nativo).
-- btree_gist: lo usarán las restricciones EXCLUDE de disponibilidad (14.4) y reservas (14.6).
-- En Supabase el esquema "extensions" ya existe; el "if not exists" lo hace repetible.

create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
