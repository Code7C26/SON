// Correo saliente. Si el servidor no tiene SMTP configurado, no se inventa un envío:
// se avisa y la visita igual queda guardada.
let nodemailer = null;
try {
    nodemailer = require('nodemailer');
} catch {
    nodemailer = null;
}

function correoConfigurado() {
    return Boolean(nodemailer && process.env.SMTP_USER && process.env.SMTP_PASS);
}

function motivoSinCorreo() {
    if (!nodemailer) return 'Falta instalar el envío de correo en el servidor.';
    return 'Falta el Gmail de SIMA y su clave de aplicación. Sin eso el aviso queda armado pero no sale.';
}

async function enviarCorreo({ para, asunto, texto, html, adjuntos }) {
    if (!correoConfigurado()) return { enviado: false, motivo: motivoSinCorreo() };
    const puerto = Number(process.env.SMTP_PORT || 587);
    const desde = process.env.SMTP_FROM || `SIMA Ambiente <${process.env.SMTP_USER}>`;
    const transporte = nodemailer.createTransport({
        host: process.env.SMTP_HOST || 'smtp.gmail.com',
        port: puerto,
        secure: process.env.SMTP_SECURE === '1' || puerto === 465,
        auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });
    await transporte.sendMail({
        from: desde,
        to: para,
        subject: asunto,
        text: texto,
        html,
        attachments: adjuntos,
    });
    return { enviado: true };
}

module.exports = { correoConfigurado, enviarCorreo };
