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
create extension if not exists pgcrypto;
