PipeCorp3D
Simulador Laboral 3D de Gasfitería con Arquitectura Cliente-Servidor y Economía Viva

Portafolio de Título PTY4479 - Analista Programador Computacional (Duoc UC)

Desarrollador: Yolzer Awidan Saravia San Martín

📖 Descripción del Proyecto
PipeCorp3D es una herramienta lúdica y formativa diseñada para resolver un problema crítico en la capacitación técnica: la falta de un entorno seguro para practicar habilidades de gasfitería sin asumir riesgos económicos o legales reales.

El jugador toma el control de una PYME de servicios de gasfitería, interactuando en un entorno 3D en primera persona bajo un modelo de arquitectura limpia, donde el núcleo lógico reside de manera autoritativa en una base de datos PostgreSQL 16 y es expuesto a través de una API RESTful construida con NestJS.

🏗️ Arquitectura Técnica de 3 Capas
1. Base de Datos Autoritativa (PostgreSQL 16)
La lógica de negocio y las normativas legales están incrustadas en el motor de base de datos para asegurar integridad absoluta.

Transaccionalidad: Cumplimiento ACID estricto con nivel de aislamiento READ COMMITTED y bloqueo de fila para concurrencia.

Ledger Inmutable: Saldo del jugador gestionado mediante un modelo "append-only".

10 Tablas Normalizadas: Equipadas con 7 triggers y 12 procedimientos almacenados que validan presupuestos, controlan la capacidad de inventario y aplican multas irrevocables de la SISS.

2. Capa Intermedia (API REST con NestJS)
Tecnologías: TypeScript, TypeORM y QueryRunner.

Seguridad: Autenticación JWT asimétrica RS256 (llave pública/privada), con lista blanca estricta para mitigar ataques de confusión de algoritmo ("HS256" y "alg: none").

Protección de Datos: Cifrado de credenciales nativo con derivación de memoria intensiva (Scrypt).

Gestión de Errores: Códigos SQL nativos mapeados a la serie estandarizada PC001-PC007.

3. Cliente Front-end (Godot Engine 4.7)
GDScript Tipado: Configuración de tipado estático strict definido como error de compilación.

Simulación Determinista: Grilla posicional validada por autoridad (GridManager) y desacoplamiento estricto de Input/Lógica (PlayerController posee a PlumberEntity), preparado para multijugador asíncrono (MP-Ready).

Contrato de Interfaz: Eventos de UI y lógica desacoplados mediante el patrón SignalBus.

Persistencia Híbrida: API Fetch en inicio de sesión, complementado con almacenamiento atómico binario local (FileAccess) en formato PC3D versionado y con validación por checksum.

🚀 Instalación y Ejecución Local
Requiere Node.js, PostgreSQL 16 y Godot 4.7.

Base de Datos:

Crea una base de datos en PostgreSQL.

Ejecuta los scripts 01_schema.sql y 04_seed.sql ubicados en la carpeta database/.

API Backend:

Navega a la carpeta backend/.

Copia .env.example a .env y ajusta las credenciales de tu DB.

Ejecuta npm install.

Inicia el servidor con npm run start:dev. (Verifica que responda en http://localhost:3000/health).

Cliente Godot:

Abre el proyecto project.godot desde la carpeta /godot.

Selecciona la escena principal World.tscn y presiona Play (F5).

📊 Metodología y Aseguramiento de Calidad
Este MVP fue desarrollado en 3 Sprints ágiles bajo el marco Scrum, totalizando 63 puntos de historia validados.

Versionamiento (GitFlow): Repositorio estructurado en ramas de características (feature/*) integradas a develop sin "fast-forward", convergiendo en el release v1.0.0-mvp.

Definition of Done (DoD): Ninguna tarea es aprobada sin evidencia adjunta y cobertura de testing.

Cobertura de Pruebas (127 Test Exitosos):

run_tests.sh: Pruebas de concurrencia y triggers de SQL.

Jest y Supertest: Pruebas unitarias y End-to-End (E2E) de la API REST.

Doctor (Godot): Herramienta de diagnóstico de dependencias e inyecciones de interfaz.
