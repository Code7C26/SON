const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const pool = new Pool({
    user: process.env.DB_USER,
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD,
    port: Number(process.env.DB_PORT || 5432),
});

// En un servidor nuevo (base vacía) crea las tablas principales a partir de sql/esquema.sql.
async function crearEsquemaSiHaceFalta() {
    const existe = await pool.query("SELECT to_regclass('public.tecnicos') AS tabla");
    if (existe.rows[0].tabla) return;
    const ruta = path.join(__dirname, '..', 'sql', 'esquema.sql');
    console.log('Base de datos vacía: creando las tablas de SON...');
    const cliente = await pool.connect();
    try {
        await cliente.query(fs.readFileSync(ruta, 'utf8'));
    } finally {
        cliente.release(true); // la conexión se descarta: el esquema cambia ajustes de sesión
    }
}

async function prepararEsquema() {
    await crearEsquemaSiHaceFalta();
    await pool.query(`
        ALTER TABLE tecnicos ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
        ALTER TABLE tecnicos ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
        ALTER TABLE tecnicos ADD COLUMN IF NOT EXISTS ubicacion_en TIMESTAMPTZ;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS orden_padre_id INTEGER;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS fecha_ocurrencia DATE;
        CREATE TABLE IF NOT EXISTS admins (
            id SERIAL PRIMARY KEY,
            nombre TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS agentes (
            id SERIAL PRIMARY KEY,
            nombre TEXT NOT NULL,
            token_hash TEXT UNIQUE NOT NULL,
            creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            visto_en TIMESTAMPTZ
        );
        CREATE TABLE IF NOT EXISTS solicitudes_contacto (
            id SERIAL PRIMARY KEY,
            nombre TEXT NOT NULL,
            empresa TEXT NOT NULL,
            telefono TEXT NOT NULL,
            tecnicos INTEGER NOT NULL,
            email TEXT,
            creada_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        ALTER TABLE solicitudes_contacto ADD COLUMN IF NOT EXISTS email TEXT;

        -- Tipo de usuario del panel: 'comercial' es la dueña (ve todo) y 'admin' es Administración
        -- (técnicos superiores: solo el área técnica). Las cuentas anteriores quedan como 'admin' y
        -- asegurarAdmin() (src/auth.js) deja siempre al menos una con acceso total.
        ALTER TABLE admins ADD COLUMN IF NOT EXISTS rol TEXT NOT NULL DEFAULT 'admin';
        DO $$ BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admins_rol_check') THEN
                ALTER TABLE admins ADD CONSTRAINT admins_rol_check CHECK (rol IN ('admin', 'comercial'));
            END IF;
        END $$;

        -- Datos de contacto de cada empresa (los usa el área comercial)
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS contacto TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS telefono TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS email TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS cuit TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS notas TEXT;
        -- Datos que usa el presupuestador (los mismos de la "Base de Datos Clientes" del Excel)
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS actividad TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS riesgo TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS categoria TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS provincia TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS departamento TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS ciudad TEXT;

        -- Lo que el técnico anota en una visita para que el área comercial lo presupueste.
        -- Si se borra la orden o el técnico, la nota se conserva (por eso ON DELETE SET NULL
        -- y las copias del nombre de la empresa y del técnico).
        CREATE TABLE IF NOT EXISTS solicitudes_presupuesto (
            id SERIAL PRIMARY KEY,
            id_cliente TEXT UNIQUE,
            empresa_id INTEGER REFERENCES empresas(id),
            empresa_nombre TEXT,
            orden_id INTEGER REFERENCES ordenes(id) ON DELETE SET NULL,
            tecnico_id INTEGER REFERENCES tecnicos(id) ON DELETE SET NULL,
            tecnico_nombre TEXT,
            descripcion TEXT NOT NULL,
            cantidad INTEGER NOT NULL DEFAULT 1,
            foto BYTEA,
            foto_tipo TEXT,
            estado TEXT NOT NULL DEFAULT 'Nueva',
            nota_comercial TEXT,
            creada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            actualizada_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS solicitudes_presupuesto_estado_idx ON solicitudes_presupuesto (estado, creada_en DESC);
        CREATE INDEX IF NOT EXISTS solicitudes_presupuesto_empresa_idx ON solicitudes_presupuesto (empresa_id);

        -- Calendario, formularios de visita, seguimiento para el cliente y tiempos del equipo.
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS formulario_id INTEGER;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS puntos JSONB;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS token_seguimiento TEXT;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS pedida_por INTEGER;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS orden_ruta INTEGER;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS email_cliente TEXT;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS whatsapp_cliente TEXT;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS aviso_en TIMESTAMPTZ;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS token_informe TEXT;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS informe_pdf TEXT;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS comentarios_cierre TEXT;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS checklist_cierre JSONB;
        CREATE UNIQUE INDEX IF NOT EXISTS ordenes_token_informe_idx ON ordenes (token_informe) WHERE token_informe IS NOT NULL;
        CREATE UNIQUE INDEX IF NOT EXISTS ordenes_token_seguimiento_idx ON ordenes (token_seguimiento) WHERE token_seguimiento IS NOT NULL;
        CREATE TABLE IF NOT EXISTS formularios_visita (
            id SERIAL PRIMARY KEY,
            nombre TEXT NOT NULL,
            puntos JSONB NOT NULL DEFAULT '[]',
            activo BOOLEAN NOT NULL DEFAULT true
        );
        CREATE TABLE IF NOT EXISTS visitas (
            id SERIAL PRIMARY KEY,
            orden_id INTEGER UNIQUE,
            tecnico_id INTEGER,
            tecnico_nombre TEXT,
            cliente TEXT,
            inicio TIMESTAMPTZ,
            fin TIMESTAMPTZ,
            minutos INTEGER,
            creada_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE TABLE IF NOT EXISTS encuestas (
            id SERIAL PRIMARY KEY,
            token TEXT UNIQUE NOT NULL,
            orden_id INTEGER UNIQUE,
            cliente TEXT,
            email TEXT,
            puntaje INTEGER,
            comentario TEXT,
            creada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            respondida_en TIMESTAMPTZ
        );
        CREATE TABLE IF NOT EXISTS geocodigos (
            direccion TEXT PRIMARY KEY,
            lat DOUBLE PRECISION,
            lng DOUBLE PRECISION,
            actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    `);
    await marcarEncuestasViejasComoEnviadas();
    await prepararEsquemaDelPresupuestador();
    await prepararEsquemaDeCampo();
}

// Lo que pidieron los técnicos en la reunión de noviembre de 2026.
async function prepararEsquemaDeCampo() {
    await pool.query(`
        -- Perfil del técnico: desde dónde sale (para ordenar el recorrido), matrícula y la imagen de
        -- su firma con sello, que va sola en cada informe (el técnico ya no firma en el celular).
        ALTER TABLE tecnicos ADD COLUMN IF NOT EXISTS salida_direccion TEXT;
        ALTER TABLE tecnicos ADD COLUMN IF NOT EXISTS matricula TEXT;
        ALTER TABLE tecnicos ADD COLUMN IF NOT EXISTS firma_sello TEXT;

        -- Las visitas son en un rango horario (de hora_ejecucion a hora_hasta): el técnico maneja su horario.
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS hora_hasta TIME;

        -- Tareas que cada empresa tiene que cumplir siempre: se cargan solas en cada orden nueva.
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS tareas_fijas JSONB;

        -- Acceso del cliente a sus informes (un enlace privado que se puede activar y cortar).
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS portal_token TEXT;
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS portal_activo BOOLEAN NOT NULL DEFAULT false;
        CREATE UNIQUE INDEX IF NOT EXISTS empresas_portal_token_idx ON empresas (portal_token) WHERE portal_token IS NOT NULL;

        -- Kilometraje y gastos que carga el técnico (combustible, peajes...) para Administración.
        CREATE TABLE IF NOT EXISTS gastos (
            id SERIAL PRIMARY KEY,
            id_cliente TEXT UNIQUE,
            orden_id INTEGER REFERENCES ordenes(id) ON DELETE SET NULL,
            tecnico_id INTEGER REFERENCES tecnicos(id) ON DELETE SET NULL,
            tecnico_nombre TEXT,
            empresa_nombre TEXT,
            vehiculo TEXT,
            km_inicio INTEGER,
            km_fin INTEGER,
            tipo TEXT NOT NULL DEFAULT 'Otro',
            monto NUMERIC(14, 2),
            descripcion TEXT,
            foto BYTEA,
            foto_tipo TEXT,
            revisado BOOLEAN NOT NULL DEFAULT false,
            creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS gastos_creado_idx ON gastos (creado_en DESC);

        -- Vencimientos (extintores, mediciones, habilitaciones...): avisan antes de que se venzan.
        CREATE TABLE IF NOT EXISTS vencimientos (
            id SERIAL PRIMARY KEY,
            id_cliente TEXT UNIQUE,
            empresa_id INTEGER REFERENCES empresas(id) ON DELETE SET NULL,
            empresa_nombre TEXT,
            orden_id INTEGER REFERENCES ordenes(id) ON DELETE SET NULL,
            tecnico_id INTEGER REFERENCES tecnicos(id) ON DELETE SET NULL,
            descripcion TEXT NOT NULL,
            cantidad INTEGER NOT NULL DEFAULT 1,
            vence DATE NOT NULL,
            resuelto BOOLEAN NOT NULL DEFAULT false,
            avisado_en TIMESTAMPTZ,
            creado_por TEXT,
            creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS vencimientos_vence_idx ON vencimientos (vence) WHERE resuelto = false;

        -- CRM comercial: tipo de cliente (define cada cuántos días hay que contactarlo), bitácora de
        -- contactos con pendientes, y por qué se perdió un presupuesto.
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS tipo_cliente TEXT;
        ALTER TABLE presupuestos ADD COLUMN IF NOT EXISTS razon_perdida TEXT;
        ALTER TABLE presupuestos ADD COLUMN IF NOT EXISTS servicio TEXT;
        CREATE TABLE IF NOT EXISTS crm_notas (
            id SERIAL PRIMARY KEY,
            empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
            fecha DATE NOT NULL DEFAULT CURRENT_DATE,
            tipo TEXT NOT NULL DEFAULT 'Llamada',
            texto TEXT,
            pendiente TEXT,
            pendiente_fecha DATE,
            pendiente_responsable TEXT,
            pendiente_hecho BOOLEAN NOT NULL DEFAULT false,
            autor TEXT,
            creada_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS crm_notas_empresa_idx ON crm_notas (empresa_id, fecha DESC);

        -- Formularios de control digitales (convertidos desde el Excel que ya usaban).
        ALTER TABLE formularios_visita ADD COLUMN IF NOT EXISTS definicion JSONB;
        ALTER TABLE formularios_visita ADD COLUMN IF NOT EXISTS archivo TEXT;
        -- Los formularios de cada orden (copia al armarla) y lo que completó el técnico.
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS formularios JSONB;
        ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS formularios_cierre JSONB;
        -- Formularios que una empresa lleva siempre (se cargan solos en cada orden nueva).
        ALTER TABLE empresas ADD COLUMN IF NOT EXISTS formularios_fijos JSONB;
    `);
}

// Las encuestas viejas se crearon al mandar el mail, antes de guardar la hora de envío.
// Se marca una sola vez: el día que aparece la columna. Después solo cuenta un envío que salió bien.
async function marcarEncuestasViejasComoEnviadas() {
    const columna = await pool.query(`
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'encuestas' AND column_name = 'enviada_en'
    `);
    if (columna.rows.length) return;
    await pool.query('ALTER TABLE encuestas ADD COLUMN enviada_en TIMESTAMPTZ');
    await pool.query('UPDATE encuestas SET enviada_en = creada_en WHERE enviada_en IS NULL');
}

// Presupuestador: configuración, inflación mensual, tarifario, costos internos y presupuestos.
// Los meses se guardan como texto "AAAA-MM" y las variaciones de inflación como fracción (0.029 = 2,9 %).
async function prepararEsquemaDelPresupuestador() {
    await pool.query(`
        CREATE TABLE IF NOT EXISTS configuracion_comercial (
            clave TEXT PRIMARY KEY,
            valor JSONB NOT NULL,
            actualizada_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );

        -- Inflación mensual (IPC nacional del INDEC). Lo que carga una persona a mano ('Manual')
        -- no lo pisa la actualización automática.
        CREATE TABLE IF NOT EXISTS ipc_mensual (
            mes TEXT PRIMARY KEY CHECK (mes ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
            variacion NUMERIC(8, 6) NOT NULL,
            fuente TEXT NOT NULL DEFAULT 'INDEC',
            actualizada_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );

        -- Tarifario: honorarios de referencia (CIEC, Colegio de Geólogos u otros). Se actualizan por
        -- inflación desde su mes base. Si tienen "modulos", el valor es módulos x valor del módulo.
        CREATE TABLE IF NOT EXISTS tarifas (
            id SERIAL PRIMARY KEY,
            familia TEXT NOT NULL,
            servicio TEXT NOT NULL,
            tramo TEXT NOT NULL DEFAULT '',
            detalle TEXT,
            nota TEXT,
            alcance TEXT,
            valor_base NUMERIC(14, 2),
            mes_base TEXT NOT NULL CHECK (mes_base ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
            indexa BOOLEAN NOT NULL DEFAULT true,
            modulos NUMERIC(8, 2),
            activa BOOLEAN NOT NULL DEFAULT true,
            creada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            actualizada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            UNIQUE (familia, servicio, tramo)
        );

        -- Costos internos de la empresa (hora de técnico, viáticos, hotel...): sirven para calcular el margen.
        CREATE TABLE IF NOT EXISTS costos_internos (
            id SERIAL PRIMARY KEY,
            concepto TEXT NOT NULL UNIQUE,
            unidad TEXT NOT NULL DEFAULT 'unidad',
            valor_base NUMERIC(14, 2),
            mes_base TEXT NOT NULL CHECK (mes_base ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
            indexa BOOLEAN NOT NULL DEFAULT true,
            creada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            actualizada_en TIMESTAMPTZ NOT NULL DEFAULT now()
        );

        -- Un presupuesto. Cada actualización ("act") es una versión nueva con el mismo número.
        CREATE TABLE IF NOT EXISTS presupuestos (
            id SERIAL PRIMARY KEY,
            numero INTEGER NOT NULL,
            version INTEGER NOT NULL DEFAULT 1,
            empresa_id INTEGER REFERENCES empresas(id) ON DELETE SET NULL,
            cliente JSONB NOT NULL DEFAULT '{}'::jsonb,
            fecha DATE NOT NULL,
            mes_referencia TEXT NOT NULL CHECK (mes_referencia ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
            estado TEXT NOT NULL DEFAULT 'Borrador',
            bonificacion NUMERIC(6, 4) NOT NULL DEFAULT 0,
            iva NUMERIC(6, 4) NOT NULL DEFAULT 0.21,
            forma_pago TEXT,
            plazo_entrega TEXT,
            validez TEXT,
            referencia TEXT,
            observaciones TEXT,
            fecha_envio DATE,
            creado_por TEXT,
            creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
            UNIQUE (numero, version)
        );
        CREATE INDEX IF NOT EXISTS presupuestos_empresa_idx ON presupuestos (empresa_id);
        CREATE INDEX IF NOT EXISTS presupuestos_estado_idx ON presupuestos (estado);

        -- Seguimiento comercial (tablero): quién lo está llevando, para cuándo y si ya se facturó.
        ALTER TABLE presupuestos ADD COLUMN IF NOT EXISTS prioridad TEXT NOT NULL DEFAULT 'media';
        ALTER TABLE presupuestos ADD COLUMN IF NOT EXISTS responsable TEXT;
        ALTER TABLE presupuestos ADD COLUMN IF NOT EXISTS fecha_limite DATE;
        ALTER TABLE presupuestos ADD COLUMN IF NOT EXISTS facturado BOOLEAN NOT NULL DEFAULT false;
        ALTER TABLE presupuestos ADD COLUMN IF NOT EXISTS nota_seguimiento TEXT;

        CREATE TABLE IF NOT EXISTS presupuesto_items (
            id SERIAL PRIMARY KEY,
            presupuesto_id INTEGER NOT NULL REFERENCES presupuestos(id) ON DELETE CASCADE,
            orden INTEGER NOT NULL,
            tarifa_id INTEGER REFERENCES tarifas(id) ON DELETE SET NULL,
            descripcion TEXT NOT NULL,
            alcance TEXT,
            cantidad NUMERIC(10, 2) NOT NULL DEFAULT 1,
            precio_unitario NUMERIC(14, 2) NOT NULL DEFAULT 0,
            precio_origen TEXT NOT NULL DEFAULT 'manual',
            valor_base NUMERIC(14, 2),
            mes_base TEXT,
            periodicidad TEXT NOT NULL DEFAULT 'mensual',
            prorratear_meses INTEGER,
            bonificable BOOLEAN NOT NULL DEFAULT true,
            costeo JSONB NOT NULL DEFAULT '[]'::jsonb,
            UNIQUE (presupuesto_id, orden)
        );

        -- Qué notas de técnicos se presupuestaron en cada presupuesto.
        CREATE TABLE IF NOT EXISTS presupuesto_solicitudes (
            presupuesto_id INTEGER NOT NULL REFERENCES presupuestos(id) ON DELETE CASCADE,
            solicitud_id INTEGER NOT NULL REFERENCES solicitudes_presupuesto(id) ON DELETE CASCADE,
            PRIMARY KEY (presupuesto_id, solicitud_id)
        );
    `);
}

module.exports = { pool, prepararEsquema };
