/**
 * End-to-end DoD for "API REST: Setup y Autenticación".
 * Requires: PostgreSQL running with database/01..04 applied, .env filled, `npm run keys` done.
 */
import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import type { Server } from 'node:http';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/app.setup';

const b64url = (input: string | Buffer): string => Buffer.from(input).toString('base64url');

describe('Auth + JWT RS256 (e2e)', () => {
  let app: INestApplication;
  let server: Server;
  const username: string = `e2e_${Date.now()}`;
  const password: string = 'Plomero_Seguro_2026';
  let token: string = '';

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    server = app.getHttpServer() as Server;
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health -> 200 with DB up', async () => {
    const res = await request(server).get('/health').expect(200);
    expect(res.body).toEqual({ status: 'ok', db: 'up' });
  });

  it('POST /auth/register -> 201, profile created by sp_register_player with starting money', async () => {
    const res = await request(server).post('/auth/register').send({ username, password }).expect(201);
    expect(res.body.username).toBe(username);
    expect(res.body.money).toBe(50000);
    expect(res.body.entityId).toBe('Player_1');
    expect(res.body.isGameOver).toBe(false);
    expect(JSON.stringify(res.body)).not.toContain('password');
  });

  it('POST /auth/register duplicate -> 409 (SQLSTATE 23505 mapped)', async () => {
    const res = await request(server).post('/auth/register').send({ username, password }).expect(409);
    expect(res.body.code).toBe('23505');
  });

  it('POST /auth/register invalid payload -> 400 (ValidationPipe)', async () => {
    await request(server).post('/auth/register').send({ username: 'a', password: '123' }).expect(400);
    await request(server).post('/auth/register').send({ username, password, isAdmin: true }).expect(400);
  });

  it('POST /auth/login wrong password -> 401 generic message', async () => {
    const res = await request(server).post('/auth/login').send({ username, password: 'wrong-password' }).expect(401);
    expect(res.body.message).toBe('Invalid credentials');
  });

  it('POST /auth/login unknown user -> 401 with the SAME message (no user enumeration)', async () => {
    const res = await request(server)
      .post('/auth/login')
      .send({ username: 'ghost_user_x', password: 'whatever123' })
      .expect(401);
    expect(res.body.message).toBe('Invalid credentials');
  });

  it('POST /auth/login -> 200 with an RS256-signed token', async () => {
    const res = await request(server).post('/auth/login').send({ username, password }).expect(200);
    token = res.body.access_token as string;
    const header: { alg: string; typ: string } = JSON.parse(
      Buffer.from(token.split('.')[0] ?? '', 'base64url').toString('utf8'),
    );
    expect(header.alg).toBe('RS256');
    expect(res.body.token_type).toBe('Bearer');
  });

  it('GET /profile without token -> 401', async () => {
    await request(server).get('/profile').expect(401);
  });

  it('GET /profile with token -> 200 authoritative state', async () => {
    const res = await request(server).get('/profile').set('Authorization', `Bearer ${token}`).expect(200);
    expect(res.body.username).toBe(username);
    expect(res.body.vehicleName).toBe('A pie');
    expect(res.body.inventoryCapacity).toBe(10);
  });

  it('GET /profile with tampered payload -> 401 (signature check)', async () => {
    const [h, , s] = token.split('.');
    const forgedPayload: string = b64url(JSON.stringify({ sub: '00000000-0000-0000-0000-000000000000', username: 'x' }));
    await request(server).get('/profile').set('Authorization', `Bearer ${h}.${forgedPayload}.${s}`).expect(401);
  });

  it('GET /profile with HS256 token signed using the PUBLIC key -> 401 (alg-confusion attack blocked)', async () => {
    const publicKey: string = readFileSync(process.env.JWT_PUBLIC_KEY_PATH ?? 'keys/public.pem', 'utf8');
    const header: string = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
    const payload: string = b64url(
      JSON.stringify({ sub: 'attacker', username, entity: 'Player_1', iss: 'pipecorp3d-api', exp: 9999999999 }),
    );
    const sig: string = createHmac('sha256', publicKey).update(`${header}.${payload}`).digest('base64url');
    await request(server).get('/profile').set('Authorization', `Bearer ${header}.${payload}.${sig}`).expect(401);
  });

  it('GET /profile with alg "none" token -> 401', async () => {
    const header: string = b64url(JSON.stringify({ alg: 'none', typ: 'JWT' }));
    const payload: string = b64url(JSON.stringify({ sub: 'attacker', iss: 'pipecorp3d-api' }));
    await request(server).get('/profile').set('Authorization', `Bearer ${header}.${payload}.`).expect(401);
  });
});
