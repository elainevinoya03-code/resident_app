class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yxcgfyoxrjgfxqxtzdik.supabase.co',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl4Y2dmeW94cmpnZnhxeHR6ZGlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxMzk0NDUsImV4cCI6MjEwMjcxNTQ0NX0.Tg-rUW4hasZTjAWvMhrz69u_wHwcoQPTgfIN1BBP6kU',
  );
}