/* Idioma de la página pública de SON (español / inglés).
 *
 * Los textos están escritos en español en el HTML; este archivo los pasa al inglés
 * buscando cada texto en EN. El idioma elegido se guarda con la misma clave que usan
 * el panel (/panel/) y la app del técnico (/tecnico/), así que se comparte entre los tres.
 */
(function () {
  var EN = {
    // Página principal
    'Plataforma de gestión operativa para equipos en terreno: órdenes, app de campo con GPS, informes en PDF y seguimiento en vivo.':
      'Operations management platform for field teams: work orders, a GPS field app, PDF reports and live tracking.',
    'SON, inicio': 'SON, home',
    'Principal': 'Main',
    'Pie': 'Footer',
    'Idioma': 'Language',
    'Plataforma': 'Platform',
    'Funciones': 'Features',
    'Demo': 'Demo',
    'Preguntas': 'FAQ',
    'Ingresar': 'Sign in',
    'Pedir demo': 'Request a demo',
    'Abrir menú': 'Open menu',
    'Gestión operativa en terreno': 'Field operations management',
    'Toda su operación técnica,': 'Your entire technical operation,',
    'sincronizada y bajo control': 'synced and under control',
    '100% digital': '100% digital',
    'auditada en tiempo real': 'audited in real time',
    'Órdenes, app de campo con GPS e informes en PDF en una sola plataforma.': 'Work orders, a GPS field app and PDF reports in a single platform.',
    'Ver demo': 'Watch demo',
    'Digital, sin papel': 'Digital, paperless',
    'Presencia validada': 'Verified presence',
    '1 clic': '1 click',
    'Informe en PDF': 'PDF report',
    'Técnico con casco revisando su celular en obra': 'Technician in a hard hat checking their phone on site',
    'ORDEN #128': 'ORDER #128',
    'En curso': 'In progress',
    'Relevamiento de extintores': 'Fire extinguisher survey',
    'Planta industrial · 09:30 a 12:00': 'Industrial plant · 09:30 to 12:00',
    '8 de 12': '8 of 12',
    'Informe enviado': 'Report sent',
    'Visita completada': 'Visit completed',
    'Cómo funciona': 'How it works',
    'Del campo al informe,': 'From the field to the report,',
    'sin pasos manuales': 'with no manual steps',
    'Planificación': 'Planning',
    'Órdenes, recurrencias y checklist asignados desde el panel.': 'Orders, recurrences and checklists assigned from the panel.',
    'Ejecución con GPS': 'GPS-verified execution',
    'Check-in en el sitio, fotos, controles y firmas, con o sin conexión.': 'On-site check-in, photos, checks and signatures, online or offline.',
    'Informe automático': 'Automatic report',
    'El PDF se arma solo con evidencias y se envía al cliente.': 'The PDF builds itself with the evidence and is sent to the client.',
    'Seguimiento': 'Follow-up',
    'Indicadores, vencimientos y encuestas de satisfacción en vivo.': 'Live indicators, expirations and satisfaction surveys.',
    'Por qué SON': 'Why SON',
    'Funciones que': 'Features that',
    'ordenan el trabajo': 'organize the work',
    'Todo en un lugar': 'Everything in one place',
    'Equipo de coordinación siguiendo la operación en sus monitores': 'Coordination team following the operation on their screens',
    'Agenda en vivo': 'Live schedule',
    'Técnico con casco y chaleco trabajando en obra': 'Technician in a hard hat and vest working on site',
    'Sin conexión': 'Works offline',
    'Fotos y firmas': 'Photos and signatures',
    'Check-in GPS': 'GPS check-in',
    'Formularios propios': 'Your own forms',
    'App de campo': 'Field app',
    'Cliente y asesor revisando el informe de la visita en la computadora': 'Client and advisor reviewing the visit report on the computer',
    'Clientes informados': 'Informed clients',
    'Módulos': 'Modules',
    'Recurrentes': 'Recurring',
    'Vencimientos': 'Expirations',
    'Presupuestos': 'Quotes',
    'Gastos': 'Expenses',
    'Análisis': 'Analytics',
    'Vea a SON': 'See SON',
    'en funcionamiento': 'in action',
    'Activar sonido': 'Turn on sound',
    'Todo sobre SON,': 'All about SON,',
    'explicado': 'explained',
    'Trabajo en campo': 'Field work',
    'Clientes': 'Clients',
    'Cuenta y acceso': 'Account and access',
    '¿Qué es SON?': 'What is SON?',
    'Una plataforma para coordinar equipos en terreno: la oficina arma las órdenes, el técnico las ejecuta desde el celular y el sistema genera el informe para el cliente.':
      'A platform to coordinate field teams: the office creates the orders, the technician carries them out from their phone and the system generates the report for the client.',
    '¿Necesito instalar algo?': 'Do I need to install anything?',
    'El panel funciona desde el navegador. Los técnicos usan la app en el celular.': 'The panel works in the browser. Technicians use the app on their phone.',
    '¿Puedo usar mis propios formularios?': 'Can I use my own forms?',
    'Sí. Se cargan checklists y planillas propias, incluso importándolas desde Excel.': 'Yes. You can load your own checklists and sheets, even importing them from Excel.',
    '¿Funciona sin señal?': 'Does it work without signal?',
    'Sí. La app guarda todo en el celular y lo envía cuando vuelve la conexión.': 'Yes. The app stores everything on the phone and sends it when the connection is back.',
    '¿Cómo se valida que el técnico estuvo en el lugar?': 'How do you verify the technician was on site?',
    'Con el check-in por GPS al iniciar el trabajo, más fotos y firmas del cliente.': 'With a GPS check-in when the job starts, plus photos and the client\'s signature.',
    '¿Cómo recibe el cliente el informe?': 'How does the client receive the report?',
    'Por correo, en PDF, apenas el técnico finaliza la visita. También puede responder una encuesta de satisfacción.':
      'By email, as a PDF, as soon as the technician finishes the visit. They can also answer a satisfaction survey.',
    '¿El cliente sabe cuándo llega el técnico?': 'Does the client know when the technician arrives?',
    'Sí. Recibe un aviso cuando el técnico sale hacia su domicilio.': 'Yes. They get a notice when the technician heads to their address.',
    '¿Quién puede ver cada sección?': 'Who can see each section?',
    'Cada usuario entra con su correo y contraseña, y ve solo las secciones de su rol.': 'Each user signs in with their email and password and only sees the sections for their role.',
    '¿Cómo empiezo?': 'How do I get started?',
    'Pida una demo: le mostramos la plataforma con su forma de trabajo y armamos su cuenta.': 'Request a demo: we show you the platform with your way of working and set up your account.',
    'Correo': 'Email',
    'Digitalice su operación': 'Digitize your operation',
    'en terreno': 'in the field',
    'Nombre y apellido': 'Full name',
    'Nombre Apellido': 'First Last',
    'Empresa': 'Company',
    'nombre@empresa.com': 'name@company.com',
    'Teléfono': 'Phone',
    'Técnicos en campo': 'Field technicians',
    'Elegir': 'Choose',
    '1 a 5 técnicos': '1 to 5 technicians',
    '6 a 15 técnicos': '6 to 15 technicians',
    '16 a 50 técnicos': '16 to 50 technicians',
    'Más de 50 técnicos': 'More than 50 technicians',
    'Mensaje': 'Message',
    'Opcional': 'Optional',
    'Enviando...': 'Sending...',
    '¡Listo! Le escribimos a la brevedad.': 'Done! We will get back to you shortly.',
    'Su operación,': 'Your operation,',
    'en un solo lugar': 'in one place',
    'Privacidad': 'Privacy',
    '© 2026 SON — Sistema de Gestión Operativa.': '© 2026 SON — Operations Management System.',

    // Política de privacidad
    'Política de privacidad — SON': 'Privacy policy — SON',
    'Qué datos usa la app de campo de SON, para qué y cómo pedir su eliminación.': 'What data the SON field app uses, what for, and how to request its deletion.',
    'Política de': 'Privacy',
    'privacidad': 'policy',
    'Última actualización: 13 de noviembre de 2026': 'Last updated: November 13, 2026',
    'Esta política explica qué datos usa SON —el panel web y la app de campo para técnicos— y para qué. SON es una herramienta de trabajo: la usan empresas para coordinar a su propio personal en terreno. Cada empresa cliente decide quién tiene cuenta y es responsable de los datos que carga.':
      'This policy explains what data SON —the web panel and the field app for technicians— uses and what for. SON is a work tool: companies use it to coordinate their own field staff. Each client company decides who has an account and is responsible for the data it uploads.',
    'Quién puede usar la app': 'Who can use the app',
    'La app de campo es solo para técnicos que tienen una cuenta creada por su empleador. No tiene registro abierto al público.':
      'The field app is only for technicians with an account created by their employer. There is no public sign-up.',
    'Qué datos usamos y para qué': 'What data we use and what for',
    'Dato': 'Data',
    'Para qué': 'What for',
    'Nombre y correo del técnico': 'Technician name and email',
    'Iniciar sesión e identificar quién hizo cada visita.': 'Signing in and identifying who made each visit.',
    'Ubicación GPS': 'GPS location',
    'Validar el check-in al llegar a cada visita y,': 'Validating the check-in on arrival at each visit and,',
    'mientras la app está abierta': 'while the app is open',
    ', mostrarle a la oficina dónde está el equipo y ordenar el recorrido del día. La app no usa la ubicación cuando está cerrada.':
      ', showing the office where the team is and ordering the day\'s route. The app does not use location when it is closed.',
    'Fotos (cámara o galería)': 'Photos (camera or gallery)',
    'Adjuntar evidencias del trabajo a la orden.': 'Attaching evidence of the work to the order.',
    'Firmas, notas, checklists y gastos': 'Signatures, notes, checklists and expenses',
    'Completar la orden de trabajo y armar el informe para el cliente.': 'Completing the work order and building the report for the client.',
    'Datos guardados en el celular': 'Data stored on the phone',
    'Que la app funcione sin señal: lo pendiente se envía cuando vuelve la conexión.': 'Letting the app work without signal: pending items are sent when the connection is back.',
    'No usamos los datos para publicidad, no los vendemos y no los compartimos con terceros, salvo los proveedores de infraestructura que alojan el servicio.':
      'We do not use the data for advertising, we do not sell it and we do not share it with third parties, except the infrastructure providers that host the service.',
    'Dónde se guardan': 'Where it is stored',
    'En los servidores de SON, con conexión cifrada (HTTPS). Los informes de cada visita se entregan a la empresa cliente que los encargó.':
      'On SON servers, over an encrypted connection (HTTPS). The reports for each visit are delivered to the client company that requested them.',
    'Cuánto tiempo': 'How long',
    'Mientras la empresa cliente mantenga su cuenta activa, o lo que exija la normativa de higiene, seguridad y medio ambiente aplicable a sus registros. Cuando la empresa cierra la cuenta, los datos se eliminan.':
      'For as long as the client company keeps its account active, or as long as the health, safety and environmental regulations applicable to its records require. When the company closes its account, the data is deleted.',
    'Tus derechos y cómo borrar tus datos': 'Your rights and how to delete your data',
    'Podés pedir acceso, corrección o eliminación de tus datos y de tu cuenta escribiendo a': 'You can request access to, correction or deletion of your data and your account by writing to',
    'o pidiéndoselo a tu empleador. Respondemos en un plazo máximo de 10 días hábiles, según la Ley 25.326 de Protección de los Datos Personales (Argentina).':
      'or by asking your employer. We respond within 10 business days at most, under Law 25,326 on Personal Data Protection (Argentina).',
    'Permisos del celular': 'Phone permissions',
    'La app pide permiso de ubicación y de cámara solo cuando hacen falta. Podés quitarlos cuando quieras desde la configuración del celular; sin la ubicación no se puede hacer el check-in.':
      'The app asks for location and camera permission only when needed. You can revoke them at any time in your phone settings; without location the check-in cannot be done.',
    'Cambios': 'Changes',
    'Si esta política cambia, actualizamos la fecha de arriba y avisamos dentro de la app.': 'If this policy changes, we update the date above and let you know in the app.',
    'Contacto': 'Contact'
  };

  var CLAVE_PANEL = 'son_admin_idioma';
  var CLAVE_TECNICO = 'son_datos/idioma.json';
  var ATRIBUTOS = ['placeholder', 'aria-label', 'alt', 'title', 'content'];
  var oyentes = [];
  var textos = [];
  var atributos = [];
  var actual = 'es';

  function limpio(texto) { return texto.replace(/\s+/g, ' ').trim(); }
  function t(es) { return actual === 'en' && EN[limpio(es)] || es; }

  function leerGuardado() {
    try {
      var guardado = localStorage.getItem(CLAVE_PANEL);
      if (guardado === 'es' || guardado === 'en') return guardado;
    } catch (e) {}
    var navegador = (navigator.language || 'es').toLowerCase();
    return navegador.indexOf('en') === 0 ? 'en' : 'es';
  }

  function guardar(codigo) {
    try {
      localStorage.setItem(CLAVE_PANEL, codigo);
      localStorage.setItem(CLAVE_TECNICO, JSON.stringify(codigo));
    } catch (e) {}
  }

  // Junta una sola vez los textos y atributos traducibles con su versión en español.
  function recolectar() {
    var caminante = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: function (nodo) {
        var padre = nodo.parentNode;
        if (!padre || /^(SCRIPT|STYLE)$/.test(padre.nodeName)) return NodeFilter.FILTER_REJECT;
        if (padre.closest && padre.closest('[data-sin-traducir]')) return NodeFilter.FILTER_REJECT;
        return EN[limpio(nodo.nodeValue)] ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      }
    });
    var nodo;
    while ((nodo = caminante.nextNode())) textos.push({ nodo: nodo, es: nodo.nodeValue });

    var elementos = document.querySelectorAll('[placeholder],[aria-label],[alt],[title],meta[name="description"]');
    Array.prototype.forEach.call(elementos, function (el) {
      ATRIBUTOS.forEach(function (atr) {
        var valor = el.getAttribute(atr);
        if (valor && EN[limpio(valor)]) atributos.push({ el: el, atr: atr, es: valor });
      });
    });
    textos.titulo = document.title;
  }

  function aplicar(codigo) {
    actual = codigo;
    document.documentElement.lang = codigo;
    textos.forEach(function (x) {
      if (codigo === 'es') { x.nodo.nodeValue = x.es; return; }
      // Conserva los espacios de alrededor para no pegar palabras.
      var inicio = x.es.match(/^\s*/)[0];
      var fin = x.es.match(/\s*$/)[0];
      x.nodo.nodeValue = inicio + EN[limpio(x.es)] + fin;
    });
    atributos.forEach(function (x) { x.el.setAttribute(x.atr, codigo === 'en' ? EN[limpio(x.es)] : x.es); });
    document.title = t(textos.titulo);
    Array.prototype.forEach.call(document.querySelectorAll('.idioma [data-idioma]'), function (boton) {
      boton.setAttribute('aria-pressed', boton.getAttribute('data-idioma') === codigo ? 'true' : 'false');
    });
    oyentes.forEach(function (fn) { fn(codigo); });
  }

  window.SONIdioma = {
    t: t,
    actual: function () { return actual; },
    alCambiar: function (fn) { oyentes.push(fn); }
  };

  function iniciar() {
    recolectar();
    Array.prototype.forEach.call(document.querySelectorAll('.idioma [data-idioma]'), function (boton) {
      boton.addEventListener('click', function () {
        var codigo = boton.getAttribute('data-idioma');
        if (codigo === actual) return;
        guardar(codigo);
        aplicar(codigo);
      });
    });
    aplicar(leerGuardado());
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar);
  else iniciar();
})();
