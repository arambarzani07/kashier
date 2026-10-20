-- DO NOT RUN AGAINST SUPABASE PRODUCTION.
-- Minimal auth-role scaffolding for a disposable PostgreSQL 17 GitHub service.
-- This does not simulate the complete Supabase Auth, Storage or Realtime services.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create role pgrst nologin;
create schema if not exists auth;
create table auth.users(id uuid primary key);
create or replace function auth.uid()
returns uuid language sql stable set search_path=''
as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
-- Production Supabase locates trusted extension functions in the dedicated extensions schema.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
alter database kashier_replay set search_path to public, extensions;
