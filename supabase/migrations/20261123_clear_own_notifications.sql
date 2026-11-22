grant delete on public.notifications to authenticated;

drop policy if exists notifications_delete_self on public.notifications;
create policy notifications_delete_self
  on public.notifications
  for delete
  to authenticated
  using (user_id = (select auth.uid()) and public.app_is_family_member(family_id));
