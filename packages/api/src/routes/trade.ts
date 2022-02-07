import { FastifyPluginAsync, FastifyRequest } from 'fastify'
import { PLAYER_MINT_TIMESTAMP, TRADE_DURATION_MILLIS } from '../constants'

import {
  AuthorizationHeader,
  JwtVerifyPayload,
  Resource,
  TradeResult,
  TradeParams,
  TradeHistoryResponse,
  TradeHistoryParams,
} from '../types'
import {
  calculateRemainingCooldown,
  isTimeToMint,
  printRemainingMillis,
} from '../utils'
import { Bufficorn } from '../domain/bufficorn'

const trades: FastifyPluginAsync = async (fastify, opts): Promise<void> => {
  if (!fastify.mongo.db) throw Error('mongo db not found')

  const { playerModel, bufficornModel, tradeModel } = fastify

  fastify.post<{ Body: TradeParams; Reply: TradeResult | Error }>('/trades', {
    schema: {
      body: TradeParams,
      headers: AuthorizationHeader,
      response: {
        200: TradeResult,
      },
    },
    handler: async (request: FastifyRequest<{ Body: TradeParams }>, reply) => {
      // Check 0: trade period
      if (PLAYER_MINT_TIMESTAMP && isTimeToMint())
        return reply.status(403).send(new Error(`Trade period is over.`))

      // Cooldown parameter is only allowed in tests
      if (process.env.NODE_ENV !== 'test') {
        request.body.cooldown = undefined
      }

      // Check 1: token is valid
      let fromKey: string
      try {
        const decoded: JwtVerifyPayload = fastify.jwt.verify(
          request.headers.authorization as string
        )
        fromKey = decoded.id
      } catch (err) {
        return reply.status(403).send(new Error(`Forbidden: invalid token`))
      }

      // Check 6: from can trade (is free)
      if (
        request.body.cooldown !== 0 &&
        !fastify.sendResourceCooldowns.isValid(fromKey)
      ) {
        return reply
          .status(409)
          .send(new Error(`Players can only trade 1 player at a time`))
      }

      const toKey = request.body.to

      // Check 7: target player can trade (is free)
      if (
        request.body.cooldown !== 0 &&
        !fastify.receiveResourceCooldowns.isValid(toKey)
      ) {
        return reply
          .status(409)
          .send(new Error(`${toKey} player is already trading`))
      }

      // Add from player to the cooldown list in spite of the trade is not already completed
      // to avoid multiple requests. If the trade fails, this cooldown is reset below
      fastify.sendResourceCooldowns.add(fromKey)
      fastify.receiveResourceCooldowns.add(toKey)

      // Check 2 (unreachable): valid server issued token refers to non-existent player
      const fromPlayer = await playerModel.get(fromKey)
      if (!fromPlayer) {
        return reply
          .status(404)
          .send(new Error(`Player does not exist (key: ${fromKey})`))
      }

      // Check 3 (unreachable): trading player has been claimed
      if (!fromPlayer.token) {
        return reply
          .status(409)
          .send(new Error(`Player should be claimed before trade with others`))
      }

      // Check 4: target player exist
      const toPlayer = await playerModel.get(toKey)
      if (!toPlayer) {
        fastify.sendResourceCooldowns.delete(fromKey)
        fastify.receiveResourceCooldowns.delete(toKey)

        return reply
          .status(404)
          .send(new Error(`Wrong target player with key ${request.body.to}`))
      }

      // Check 5: target Player is claimed
      if (!toPlayer.token) {
        fastify.sendResourceCooldowns.delete(fromKey)
        fastify.receiveResourceCooldowns.delete(toKey)

        return reply
          .status(409)
          .send(new Error(`Target player has not been claimed yet`))
      }

      const currentTimestamp = Date.now()

      // Check 8: cooldown period from Player to target Player has elapsed
      const lastTrade = await tradeModel.getLast({
        from: fromPlayer.username,
        to: toPlayer.username,
      })
      const remainingCooldown: number = lastTrade
        ? calculateRemainingCooldown(lastTrade.ends)
        : 0
      if (remainingCooldown && request.body.cooldown !== 0) {
        fastify.sendResourceCooldowns.delete(fromKey)
        fastify.receiveResourceCooldowns.delete(toKey)
        return reply
          .status(409)
          .send(
            new Error(
              `${toPlayer.username} player needs ${printRemainingMillis(
                remainingCooldown
              )} to cooldown before trading with you again`
            )
          )
      }

      const resource: Resource = playerModel.generateResource(
        fromPlayer.toDbVTO(),
        lastTrade
      )

      let bufficorn: Bufficorn
      try {
        // Feed bufficorn
        bufficorn = await bufficornModel.feed(
          toPlayer.selectedBufficorn,
          resource,
          toPlayer.ranch
        )
      } catch (error) {
        fastify.sendResourceCooldowns.delete(fromKey)
        fastify.receiveResourceCooldowns.delete(toKey)

        return reply.status(403).send(error as Error)
      }

      // Update player score
      let updatedToPlayer = toPlayer
      updatedToPlayer.points += resource.amount
      playerModel.update(updatedToPlayer.toDbVTO())

      // Create and return `trade` object
      let tradeDuration
      if (request.body.cooldown === 0) {
        tradeDuration = 0
      } else {
        tradeDuration = TRADE_DURATION_MILLIS
      }
      const trade = await tradeModel.create({
        ends: currentTimestamp + tradeDuration,
        from: fromPlayer.username,
        to: toPlayer.username,
        resource,
        timestamp: currentTimestamp,
        bufficorn: bufficorn.name,
      })

      return reply.status(200).send(trade)
    },
  })

  // GET /trades?limit=LIMIT&offset=OFFSET
  fastify.get<{
    Querystring: TradeHistoryParams
    Reply: TradeHistoryResponse | Error
  }>('/trades', {
    schema: {
      querystring: TradeHistoryParams,
      headers: AuthorizationHeader,
      response: {
        200: TradeHistoryResponse,
      },
    },
    handler: async (
      request: FastifyRequest<{ Querystring: TradeHistoryParams }>,
      reply
    ) => {
      // Check 1: token is valid
      let fromKey: string
      try {
        const decoded: JwtVerifyPayload = fastify.jwt.verify(
          request.headers.authorization as string
        )
        fromKey = decoded.id
      } catch (err) {
        return reply.status(403).send(new Error(`Forbidden: invalid token`))
      }

      // Check 2 (unreachable): valid server issued token refers to non-existent player
      const player = await playerModel.get(fromKey)
      if (!player) {
        return reply
          .status(404)
          .send(new Error(`Player does not exist (key: ${fromKey})`))
      }

      // Check 3 (unreachable): trading player has been claimed
      if (!player.token) {
        return reply
          .status(409)
          .send(new Error(`Player should be claimed before trade with others`))
      }

      return reply.status(200).send({
        trades: {
          trades: await tradeModel.getManyByUsername(player.username, {
            limit: request.query.limit || 10,
            offset: request.query.offset || 0,
          }),
          total: await tradeModel.count(player.username),
        },
      })
    },
  })
}

export default trades
