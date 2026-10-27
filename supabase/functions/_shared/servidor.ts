// Utilidades comunes de las funciones de servidor (Deno).
import { createClient, type SupabaseClient, type User } from 'npm:@supabase/supabase-js@2.118.0';

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// CORS: solo los orígenes de ORIGENES_PERMITIDOS (separados por comas).
// Si la variable no existe se permite cualquiera (cómodo para probar).
export function cabecerasCors(req: Request): Record<string, string> {
  const permitidos = (Deno.env.get('ORIGENES_PERMITIDOS') ?? '')
    .split(',').map((s) => s.trim()).filter(Boolean);
  const origen = req.headers.get('origin') ?? '';
  const valor = permitidos.length === 0 ? '*' : permitidos.includes(origen) ? origen : permitidos[0];
  return {
    'Access-Control-Allow-Origin': valor,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

export function respuesta(req: Request, cuerpo: unknown, estado = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...cabecerasCors(req), 'Content-Type': 'application/json; charset=utf-8' },
  });
}

export type Contexto = { usuario: SupabaseClient; admin: SupabaseClient; user: User };

// Claves del proyecto. Supabase las inyecta en la función: las nuevas
// (publishable / secret, en JSON) y, mientras existan, las antiguas
// (anon / service_role). Se usa la que haya.
function clave(tipo: 'publica' | 'secreta'): string {
  const json = Deno.env.get(tipo === 'publica' ? 'SUPABASE_PUBLISHABLE_KEYS' : 'SUPABASE_SECRET_KEYS');
  if (json) {
    try {
      const claves = JSON.parse(json) as Record<string, string>;
      const v = claves.default ?? Object.values(claves)[0];
      if (v) return v;
    } catch { /* formato inesperado: se prueba con las antiguas */ }
  }
  const antigua = Deno.env.get(tipo === 'publica' ? 'SUPABASE_ANON_KEY' : 'SUPABASE_SERVICE_ROLE_KEY');
  if (antigua) return antigua;
  throw new Error(`No hay clave ${tipo} de Supabase en el entorno de la función`);
}

// Dos clientes: `usuario` actúa con los permisos de quien llama (RLS
// incluida) y `admin` con la clave secreta, solo para lo que la función
// ya ha autorizado.
export async function contexto(req: Request): Promise<Contexto | Response> {
  const url = Deno.env.get('SUPABASE_URL')!;
  const cabecera = req.headers.get('Authorization') ?? '';
  const token = cabecera.replace(/^Bearer\s+/i, '');
  if (!token) return respuesta(req, { error: 'No has iniciado sesión' }, 401);

  const usuario = createClient(url, clave('publica'), {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(url, clave('secreta'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  // El token hay que pasarlo explícitamente: sin él, getUser() busca una
  // sesión guardada (que en el servidor no existe) y siempre falla.
  // Además lo valida el servidor de Auth, así que no dependemos solo de la
  // comprobación previa de la plataforma (verify_jwt).
  const { data, error } = await usuario.auth.getUser(token);
  if (error || !data.user) return respuesta(req, { error: 'No has iniciado sesión' }, 401);
  return { usuario, admin, user: data.user };
}

export async function leerJson(req: Request, maxBytes: number): Promise<Record<string, unknown> | null> {
  const largo = Number(req.headers.get('content-length') ?? '0');
  if (largo > maxBytes) return null;
  const texto = await req.text();
  if (texto.length > maxBytes) return null;
  try {
    const v = JSON.parse(texto);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

// IP del cliente según la cabecera del proxy de Supabase; se descarta si
// no tiene pinta de IP (la columna es de tipo inet).
export function ipCliente(req: Request): string | null {
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim();
  return /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : null;
}

export async function rolDe(admin: SupabaseClient, userId: string): Promise<string | null> {
  const { data } = await admin.from('perfiles').select('rol').eq('id', userId).maybeSingle();
  return data?.rol ?? null;
}

export async function auditar(
  admin: SupabaseClient, userId: string, rol: string | null,
  accion: string, objeto: string, objetoId: string | null, detalle: Record<string, unknown> = {},
) {
  const { error } = await admin.from('auditoria').insert({
    usuario_id: userId, rol, accion, objeto, objeto_id: objetoId, detalle,
  });
  if (error) console.error('auditoria', error);
}
