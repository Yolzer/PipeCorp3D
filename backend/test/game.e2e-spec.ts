/**
 * End-to-end DoD for "API REST: Endpoints de Juego" — the full MVP loop over HTTP.
 * Requires the database rebuilt from database/01..04 (clean economy params).
 */
import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import type { Server } from 'node:http';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/app.setup';

interface Ticket { id: number; zone: string; status: string; budget: number; estimatedParts: number; targetSeconds: number }

describe('Game loop (e2e)', () => {
  let app: INestApplication;
  let server: Server;
  let auth: string = '';
  const username: string = `loop_${Date.now()}`;
  let tickets: Ticket[] = [];

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    server = app.getHttpServer() as Server;
    await request(server).post('/auth/register').send({ username, password: 'Plomero_Seguro_2026' }).expect(201);
    const login = await request(server).post('/auth/login').send({ username, password: 'Plomero_Seguro_2026' }).expect(200);
    auth = `Bearer ${login.body.access_token as string}`;
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /tickets without token -> 401', async () => {
    await request(server).get('/tickets').expect(401);
  });

  it('GET /tickets -> board of 3 (2 PRIVATE + 1 PUBLIC) with automatic budget', async () => {
    const res = await request(server).get('/tickets').set('Authorization', auth).expect(200);
    tickets = res.body.tickets as Ticket[];
    expect(tickets).toHaveLength(3);
    expect(tickets.map((t: Ticket) => t.zone)).toEqual(['PRIVATE', 'PRIVATE', 'PUBLIC']);
    expect(tickets[0]?.budget).toBe(8700); // 6000*1 + avg(1500,1200)*2
    expect(tickets[0]?.targetSeconds).toBe(75);
  });

  it('POST /tickets/:id/accept -> ACCEPTED and materials auto-purchased in the same transaction', async () => {
    const res = await request(server).post(`/tickets/${tickets[0]?.id}/accept`).set('Authorization', auth).expect(200);
    expect(res.body.ticket.status).toBe('ACCEPTED');
    expect(res.body.profile.money).toBe(50000 - 4 * 1200); // 2 parts + 2 spare
  });

  it('POST /jobs/:id/complete -> grade S, payout 1.5x budget, XP gained', async () => {
    const res = await request(server)
      .post(`/jobs/${tickets[0]?.id}/complete`).set('Authorization', auth)
      .send({ itemCode: 'pvc_90_deg', timeSeconds: 60, partsUsed: 2, partsWasted: 0 }).expect(200);
    expect(res.body.result).toEqual({ ticketId: tickets[0]?.id, grade: 'S', payout: 13050, xpGained: 30 });
    expect(res.body.profile.money).toBe(45200 + 13050);
    expect(res.body.profile.xp).toBe(30);
  });

  it('completing the same ticket twice -> 409 PC003', async () => {
    const res = await request(server)
      .post(`/jobs/${tickets[0]?.id}/complete`).set('Authorization', auth)
      .send({ itemCode: 'pvc_90_deg', timeSeconds: 60, partsUsed: 2, partsWasted: 0 }).expect(409);
    expect(res.body.code).toBe('PC003');
  });

  it('invalid job payload (unknown item) -> 400', async () => {
    await request(server)
      .post(`/jobs/${tickets[1]?.id}/complete`).set('Authorization', auth)
      .send({ itemCode: 'golden_pipe', timeSeconds: 60, partsUsed: 2, partsWasted: 0 }).expect(400);
  });

  it('GET /inventory -> 2 spare parts left', async () => {
    const res = await request(server).get('/inventory').set('Authorization', auth).expect(200);
    expect(res.body.items).toEqual([{ itemCode: 'pvc_90_deg', quantity: 2 }]);
  });

  it('purchase beyond vehicle capacity -> 422 PC005', async () => {
    const res = await request(server).post('/inventory/purchase').set('Authorization', auth)
      .send({ itemCode: 'pvc_straight', quantity: 5 }).expect(422);
    expect(res.body.code).toBe('PC005');
  });

  it('vehicle upgrade without XP -> 403 PC006', async () => {
    const res = await request(server).post('/vehicles/upgrade').set('Authorization', auth).send({ tierId: 2 }).expect(403);
    expect(res.body.code).toBe('PC006');
  });

  it('SISS triage: derive PUBLIC ticket -> +3000 and +10 reputation', async () => {
    const res = await request(server).post(`/tickets/${tickets[2]?.id}/derive`).set('Authorization', auth).expect(200);
    expect(res.body.profile.money).toBe(58250 + 3000);
    expect(res.body.profile.reputation).toBe(10);
  });

  it('deriving a PRIVATE ticket -> 409 PC003', async () => {
    const res = await request(server).post(`/tickets/${tickets[1]?.id}/derive`).set('Authorization', auth).expect(409);
    expect(res.body.code).toBe('PC003');
  });

  it('tampering on a PRIVATE ticket -> 409 PC003 (only PUBLIC zones are SISS)', async () => {
    await request(server).post(`/tickets/${tickets[1]?.id}/tampering`).set('Authorization', auth).expect(409);
  });

  it('after deriving, the board refills and always keeps one OPEN PUBLIC ticket', async () => {
    const res = await request(server).get('/tickets').set('Authorization', auth).expect(200);
    const board = res.body.tickets as Ticket[];
    expect(board.filter((t: Ticket) => t.zone === 'PUBLIC' && t.status === 'OPEN').length).toBeGreaterThanOrEqual(1);
  });

  it('daily upkeep drives the player to bankruptcy -> Game Over', async () => {
    let gameOver: boolean = false;
    let days: number = 0;
    while (!gameOver && days < 20) {
      const res = await request(server).post('/day/end').set('Authorization', auth).expect(200);
      gameOver = res.body.profile.isGameOver as boolean;
      days++;
      if (gameOver) expect(res.body.profile.gameOverReason).toBe('BANKRUPTCY');
    }
    expect(days).toBe(8); // 61250 / 8000 -> negative on day 8
  });

  it('any action after Game Over -> 409 PC001', async () => {
    const res = await request(server).post(`/tickets/${tickets[1]?.id}/accept`).set('Authorization', auth).expect(409);
    expect(res.body.code).toBe('PC001');
  });
});
