import { Body, Controller, Get, HttpCode, HttpStatus, Param, ParseIntPipe, Post, UseGuards } from '@nestjs/common';
import { CurrentPlayer } from '../auth/current-player.decorator';
import { JwtPayload } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CompleteJobDto, PurchaseDto, UpgradeVehicleDto } from './dto/game.dto';
import { GameService } from './game.service';
import { InventoryView, JobResultView, ProfileEnvelope, TicketView } from './game.types';

/** Gameplay endpoints (SLC scope). Every route requires the RS256 bearer token. */
@Controller()
@UseGuards(JwtAuthGuard)
export class GameController {
  constructor(private readonly game: GameService) {}

  @Get('tickets')
  tickets(@CurrentPlayer() p: JwtPayload): Promise<{ tickets: TicketView[] }> {
    return this.game.listTickets(p);
  }

  @Post('tickets/:id/accept')
  @HttpCode(HttpStatus.OK)
  accept(@CurrentPlayer() p: JwtPayload, @Param('id', ParseIntPipe) id: number): Promise<{ ticket: TicketView } & ProfileEnvelope> {
    return this.game.acceptTicket(p, id);
  }

  @Post('tickets/:id/derive')
  @HttpCode(HttpStatus.OK)
  derive(@CurrentPlayer() p: JwtPayload, @Param('id', ParseIntPipe) id: number): Promise<ProfileEnvelope> {
    return this.game.deriveTicket(p, id);
  }

  @Post('tickets/:id/tampering')
  @HttpCode(HttpStatus.OK)
  tampering(@CurrentPlayer() p: JwtPayload, @Param('id', ParseIntPipe) id: number): Promise<ProfileEnvelope> {
    return this.game.reportTampering(p, id);
  }

  @Post('jobs/:ticketId/complete')
  @HttpCode(HttpStatus.OK)
  complete(
    @CurrentPlayer() p: JwtPayload,
    @Param('ticketId', ParseIntPipe) ticketId: number,
    @Body() dto: CompleteJobDto,
  ): Promise<{ result: JobResultView } & ProfileEnvelope> {
    return this.game.completeJob(p, ticketId, dto.itemCode, dto.timeSeconds, dto.partsUsed, dto.partsWasted);
  }

  @Get('inventory')
  inventory(@CurrentPlayer() p: JwtPayload): Promise<{ items: InventoryView[] }> {
    return this.game.inventory(p);
  }

  @Post('inventory/purchase')
  @HttpCode(HttpStatus.OK)
  purchase(@CurrentPlayer() p: JwtPayload, @Body() dto: PurchaseDto): Promise<{ inventory: InventoryView } & ProfileEnvelope> {
    return this.game.purchase(p, dto.itemCode, dto.quantity);
  }

  @Post('vehicles/upgrade')
  @HttpCode(HttpStatus.OK)
  upgrade(@CurrentPlayer() p: JwtPayload, @Body() dto: UpgradeVehicleDto): Promise<ProfileEnvelope> {
    return this.game.upgradeVehicle(p, dto.tierId);
  }

  @Post('day/end')
  @HttpCode(HttpStatus.OK)
  endDay(@CurrentPlayer() p: JwtPayload): Promise<ProfileEnvelope> {
    return this.game.endDay(p);
  }
}
