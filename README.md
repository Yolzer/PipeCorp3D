<div align="center">
  <h1>🛠️️ PipeCorp3D</h1>
  <p><b>Simulador Laboral 3D de Gasfitería con Arquitectura Cliente-Servidor y Economía Viva</b></p>
  <p><i>Portafolio de Título PTY4479 - Analista Programador Computacional (Duoc UC)</i></p>
  
  ![Godot Engine](https://img.shields.io/badge/Godot_4.7-478CBF?style=for-the-badge&logo=godotengine&logoColor=white)
  ![PostgreSQL](https://img.shields.io/badge/PostgreSQL_16-316192?style=for-the-badge&logo=postgresql&logoColor=white)
  ![NestJS](https://img.shields.io/badge/NestJS-E0234E?style=for-the-badge&logo=nestjs&logoColor=white)
  ![TypeScript](https://img.shields.io/badge/TypeScript-007ACC?style=for-the-badge&logo=typescript&logoColor=white)
  ![Tests](https://img.shields.io/badge/Tests-127%2F127_Passing-success?style=for-the-badge)
</div>

## 📖 Descripción del Proyecto

**PipeCorp3D** es una herramienta lúdica y formativa diseñada para resolver un problema crítico en la capacitación técnica: la falta de un entorno seguro para practicar habilidades de gasfitería sin asumir riesgos económicos o legales reales. 

El jugador toma el control de una PYME de servicios, interactuando en un entorno 3D en primera persona bajo un modelo de arquitectura limpia, donde el núcleo lógico reside de manera autoritativa en una base de datos PostgreSQL y es expuesto a través de una API RESTful.

---

## 🏗️ Arquitectura Técnica de 3 Capas

### 1. Base de Datos Autoritativa (PostgreSQL 16)
La lógica de negocio y las normativas legales están incrustadas en el motor de BD para asegurar integridad absoluta.
- **Transaccionalidad:** Cumplimiento ACID estricto con nivel de aislamiento `READ COMMITTED` y bloqueo de fila para concurrencia.
- **Ledger Inmutable:** Saldo gestionado mediante un modelo *append-only*.
- **10 Tablas Normalizadas:** Equipadas con **7 triggers** y **12 procedimientos almacenados** que validan presupuestos, inventario y multas SISS.

### 2. Capa Intermedia (API REST con NestJS)
- **Seguridad:** Autenticación JWT asimétrica **RS256**, con lista blanca estricta para mitigar ataques de confusión de algoritmo ("HS256" y "alg: none").
- **Protección de Datos:** Cifrado de credenciales nativo con derivación de memoria intensiva (Scrypt).
- **Gestión de Errores:** Códigos SQL nativos mapeados a la serie estandarizada `PC001-PC007`.

### 3. Cliente Front-end (Godot Engine 4.7)
- **GDScript Tipado:** Configuración estática `strict` definida como `error` de compilación.
- **Simulación Determinista:** Grilla posicional validada por autoridad (`GridManager`) y desacoplamiento de Input/Lógica (`PlayerController` posee a `PlumberEntity`), preparado para multijugador asíncrono (MP-Ready).
- **Contrato de Interfaz:** Eventos de UI y lógica desacoplados mediante el patrón `SignalBus`.
- **Persistencia Híbrida:** API Fetch complementado con almacenamiento atómico binario local (`FileAccess`) en formato PC3D versionado (con checksum).

---

## 🚀 Instalación y Ejecución Local

*Requisitos: Node.js, PostgreSQL 16 y Godot 4.7.*

### 1. Base de Datos sql

# Crea la base de datos y ejecuta los scripts ubicados en /database
\i database/01_schema.sql
\i database/04_seed.sql

2. API Backend
Bash
cd backend
cp .env.example .env # Ajusta tus credenciales de BD aquí
npm install
npm run start:dev    # Verifica salud en http://localhost:3000/health

3. Cliente Godot
Abre project.godot desde la carpeta /godot.

Selecciona la escena principal World.tscn y presiona F5 para jugar.

📊 Metodología y Aseguramiento de Calidad (QA)
Este MVP fue desarrollado en 3 Sprints ágiles bajo el marco Scrum, validando un total de 63 puntos de historia.

🌿 Versionamiento (GitFlow): Ramas de características (feature/*) integradas a develop sin fast-forward, convergiendo en el release v1.0.0-mvp.

✅ Definition of Done (DoD): Cero tareas aprobadas sin evidencia adjunta y cobertura de testing.

🧪 Cobertura de Pruebas (127 Test Automatizados Exitosos):

run_tests.sh: Pruebas de concurrencia y triggers SQL.

Jest y Supertest: Unitarias y End-to-End de la API REST.

Godot Doctor / Headless: Pruebas de integración, UI y lógica estricta.
