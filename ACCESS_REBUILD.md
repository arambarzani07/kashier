# Access v2 operations

- Production: https://kashier-hazel.vercel.app
- Existing owner: select **خاوەنی هەژماری کۆنم**, authenticate with the existing email/password, then choose a globally unique username (3–40 ASCII letters/digits/dot/underscore/hyphen). The original Auth ID and business records stay intact.
- Staff accounts are created by the owner in `staff.html`, with a username, temporary password (12–128 characters), receipt name, store name, role and individual permissions. Staff need no email and accept no invitation.
- On first login or after an owner reset, staff must replace the temporary password before any business API access.
- Role destinations: owner dashboard, manager store-sales report, cashier selling screen. Managers can read store sales; costs/profit, backups and employee administration remain owner-only. Returns remain limited to the employee's own cash receipts, with full and partial return permissions separate.
- Disabling an employee blocks existing tokens immediately. Re-enabling does not reactivate earlier sessions. **دەرکردن لە هەموو ئامێرەکان** invalidates earlier sessions using a database cutoff; future sign-in remains possible. Reset invalidates sessions before changing the password, so uncertain Auth outcomes fail closed.
- **قوفڵ / گۆڕینی کارمەند** locks the current tab and requires fresh credentials while retaining actor-scoped drafts. This is a screen lock; server session revocation is a separate owner action.
- Owner enrollment is not public signup. Existing legacy staff memberships cannot enroll as new owners; owners provision their replacement employee identities directly. Historical actor IDs remain unchanged.

## Release validation

Run `node scripts/sync-static-assets.cjs`, then `node scripts/release-check.cjs`. `tests/access-rls.sql` is run inside `BEGIN`/`ROLLBACK`; it is not a real-user sign-in test. Never apply the canonical `supabase/access-rebuild.sql` again to an already-migrated database. Versioned migrations mirror the applied history. The latest service-boundary correction is required when replaying that history.

The Edge Function `access` owns password/employee provisioning. Secrets stay in its managed environment. `verify_jwt=false` is necessary for public username login; every non-login action verifies the caller through Auth, then validates its real session in the service-only database API. Do not expose `access_admin` to `anon` or `authenticated`.

Business backups exclude authentication credentials and private access profiles. Backups are not account migration files. The current restore process remains restricted to an empty original-owner workspace.
