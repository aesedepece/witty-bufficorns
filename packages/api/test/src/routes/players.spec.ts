import { BUFFICORNS_INDEX_GROUP_BY_RANCH } from '../../../src/constants'
import {
  server,
  authenticatePlayer,
  serverInject,
  initialPlayers,
} from '../../setup'

describe('player.ts', () => {
  describe('GET /players', () => {
    it('should NOT get PLAYER #1 - no authorization header', async () => {
      await serverInject(
        {
          method: 'GET',
          url: `/players/${initialPlayers[0].key}`,
        },
        (err, response) => {
          expect(response?.json().message).toBe(
            `headers should have required property 'authorization'`
          )
        }
      )
    })

    it('should NOT get PLAYER #1 - invalid jwt token', async () => {
      await serverInject(
        {
          method: 'GET',
          url: `/players/${initialPlayers[0].key}`,
          headers: {
            Authorization: 'foo',
          },
        },
        (err, response) => {
          expect(response?.json().message).toBe('Forbidden: invalid token')
        }
      )
    })

    it('should NOT get PLAYER#1 - valid token for PLAYER #2', async () => {
      await authenticatePlayer(initialPlayers[0].key)
      const token = await authenticatePlayer(initialPlayers[1].key)

      await serverInject(
        {
          method: 'GET',
          url: `/players/${initialPlayers[0].key}`,
          headers: {
            Authorization: token,
          },
        },
        (err, response) => {
          expect(err).toBeFalsy()
          expect(response.statusCode).toBe(403)
          expect(response.headers['content-type']).toBe(
            'application/json; charset=utf-8'
          )
        }
      )
    })

    it('should NOT get PLAYER #12345 - valid token but non-existent player', async () => {
      const token = await authenticatePlayer(initialPlayers[0].key)

      await serverInject(
        {
          method: 'GET',
          url: '/players/12345',
          headers: {
            Authorization: token,
          },
        },
        (err, response) => {
          expect(err).toBeFalsy()
          expect(response.statusCode).toBe(403)
          expect(response.headers['content-type']).toBe(
            'application/json; charset=utf-8'
          )
        }
      )
    })

    it('should get PLAYER #1 - get after claimed', async () => {
      const token = await authenticatePlayer(initialPlayers[0].key)

      await serverInject(
        {
          method: 'GET',
          url: `/players/${initialPlayers[0].key}`,
          headers: {
            Authorization: token,
          },
        },
        (err, response) => {
          const {
            tradeIn,
            tradeOut,
            player: {
              key,
              username,
              ranch,
              points,
              lastTradeIn,
              lastTradeOut,
              medals,
              selectedBufficorn,
              creationIndex,
            },
          } = response.json()

          expect(key).toBeTruthy()
          expect(username).toBeTruthy()
          expect(selectedBufficorn <= 23).toBeTruthy()
          expect(selectedBufficorn >= 0).toBeTruthy()
          expect(points).toBe(0)
          expect(lastTradeIn).toBe(undefined)
          expect(lastTradeOut).toBe(undefined)
          expect(medals).toStrictEqual([])
          expect(tradeIn).toBeFalsy()
          expect(tradeOut).toBeFalsy()
          expect(typeof creationIndex).toBe('number')

          // Check ranch integrity
          expect(ranch.name).toBeTruthy()
          expect(ranch.bufficorns.length).toBe(4)
          expect(ranch.bufficorns[0].name).toBeTruthy()
          expect(ranch.bufficorns[0].ranch).toBeTruthy()
          expect(typeof ranch.creationIndex).toBe('number')

          // Check bufficorn integrity
          expect(ranch.bufficorns[0].vigor).toBe(0)
          expect(ranch.bufficorns[0].speed).toBe(0)
          expect(ranch.bufficorns[0].coolness).toBe(0)
          expect(ranch.bufficorns[0].coat).toBe(0)
          expect(ranch.bufficorns[0].intelligence).toBe(0)
          expect(ranch.bufficorns[0].medals).toStrictEqual([])
          expect(typeof ranch.bufficorns[0].creationIndex).toBe('number')
        }
      )
    })
  })

  describe('POST /player/selected-bufficorn/:creationIndex', () => {
    it('Should not update selected bufficorn - no authorization header', async () => {
      await serverInject(
        {
          method: 'POST',
          url: `/players/selected-bufficorn/0`,
        },
        (err, response) => {
          expect(response?.json().message).toBe(
            `headers should have required property 'authorization'`
          )
        }
      )
    })

    it('should NOT update selected bufficorn - invalid jwt token', async () => {
      await serverInject(
        {
          method: 'POST',
          url: `/players/selected-bufficorn/0`,
          headers: {
            Authorization: 'foo',
          },
        },
        (err, response) => {
          expect(response?.json().message).toBe('Forbidden: invalid token')
        }
      )
    })

    it('should NOT update selected bufficorn - creation index greater than 24', async () => {
      const token = await authenticatePlayer(initialPlayers[0].key)

      await serverInject(
        {
          method: 'POST',
          url: `/players/selected-bufficorn/24`,
          headers: {
            authorization: token,
          },
        },
        (err, response) => {
          expect(err).toBeFalsy()
          expect(response.statusCode).toBe(404)
          expect(response.json().message).toBe(
            "Bufficorn with creationIndex 24 doesn't belong to ranch Gold Reef Co."
          )
        }
      )
    })

    it('should NOT update selected bufficorn - creation index smaller than 0', async () => {
      const token = await authenticatePlayer(initialPlayers[0].key)

      await serverInject(
        {
          method: 'POST',
          url: `/players/selected-bufficorn/-1`,
          headers: {
            authorization: token,
          },
        },
        (err, response) => {
          expect(err).toBeFalsy()
          expect(response.statusCode).toBe(404)
          expect(response.json().message).toBe(
            "Bufficorn with creationIndex -1 doesn't belong to ranch Gold Reef Co."
          )
        }
      )
    })

    it('should NOT update selected bufficorn - creation index should be an integer', async () => {
      const token = await authenticatePlayer(initialPlayers[0].key)

      await serverInject(
        {
          method: 'POST',
          url: `/players/selected-bufficorn/2.5`,
          headers: {
            authorization: token,
          },
        },
        (err, response) => {
          expect(err).toBeFalsy()
          expect(response.statusCode).toBe(400)
          expect(response.json().message).toBe(
            'params/creationIndex should be integer'
          )
        }
      )
    })

    it('should NOT update selected bufficorn - creation index should be an integer', async () => {
      const token = await authenticatePlayer(initialPlayers[0].key)

      await serverInject(
        {
          method: 'POST',
          url: `/players/selected-bufficorn/t`,
          headers: {
            authorization: token,
          },
        },
        (err, response) => {
          expect(err).toBeFalsy()
          expect(response.statusCode).toBe(400)
          expect(response.json().message).toBe(
            'params/creationIndex should be integer'
          )
        }
      )
    })

    it('should update selected bufficorn', async () => {
      const token = await authenticatePlayer(initialPlayers[0].key)

      let initialSelectedBufficorn, playerRanch

      await serverInject(
        {
          method: 'GET',
          url: `/players/${initialPlayers[0].key}`,
          headers: {
            Authorization: token,
          },
        },
        (err, response) => {
          const {
            player: {
              selectedBufficorn,
              ranch: { name },
            },
          } = response.json()
          initialSelectedBufficorn = selectedBufficorn
          playerRanch = name
        }
      )

      const bufficornPositionIndex = BUFFICORNS_INDEX_GROUP_BY_RANCH[
        playerRanch
      ].findIndex((idx) => idx === initialSelectedBufficorn)
      const newSelectedBufficorn =
        BUFFICORNS_INDEX_GROUP_BY_RANCH[playerRanch][
          bufficornPositionIndex - 1 < 0
            ? bufficornPositionIndex + 1
            : bufficornPositionIndex - 1
        ]

      await serverInject(
        {
          method: 'POST',
          url: `/players/selected-bufficorn/${newSelectedBufficorn}`,
          headers: {
            authorization: token,
          },
        },
        (err, response) => {
          expect(err).toBeFalsy()
          expect(response.statusCode).toBe(200)
          expect(response.json().creationIndex).toBe(newSelectedBufficorn)
        }
      )
    })
  })

  // test('should get EGG #1 - get after incubation', async (t) => {
  //   const token = await authenticatePlayer(initialPlayers[0].key)

  //   await new Promise((resolve) => {
  //     server.inject(
  //       {
  //         method: 'POST',
  //         url: '/trades',
  //         payload: {
  //           to,
  //         },
  //         headers: {
  //           Authorization: `${token}`,
  //         },
  //       },
  //       (err, response) => {
  //         t.error(err)
  //         t.equal(response.statusCode, 200)
  //         resolve(true)
  //       }
  //     )
  //   })

  //   await new Promise((resolve) => {
  //     server.inject(
  //       {
  //         method: 'GET',
  //         url: `/eggs/${initialEggs[0].key}`,
  //         headers: {
  //           Authorization: `${token}`,
  //         },
  //       },
  //       (err, response) => {
  //         t.error(err)
  //         t.equal(response.statusCode, 200)
  //         t.equal(
  //           response.headers['content-type'],
  //           'application/json; charset=utf-8'
  //         )
  //         t.ok(response.json().incubating)
  //         t.ok(response.json().incubatedBy)
  //         t.ok(response.json().egg)
  //         t.same(response.json().egg.rarityIndex, 0)

  //         // Check incubated by (self-incubation)
  //         t.same(response.json().incubatedBy.from, initialEggs[0].username)
  //         t.same(response.json().incubatedBy.to, initialEggs[0].username)
  //         t.ok(response.json().incubatedBy.remainingDuration > 0)
  //         t.ok(
  //           response.json().incubatedBy.remainingDuration <=
  //             INCUBATION_DURATION_MILLIS
  //         )
  //         t.ok(
  //           response.json().incubatedBy.remainingCooldown >
  //             INCUBATION_DURATION_MILLIS
  //         )
  //         t.ok(
  //           response.json().incubatedBy.remainingCooldown <=
  //             INCUBATION_DURATION_MILLIS + INCUBATION_COOLDOWN_MILLIS
  //         )

  //         // Check incubating (self-incubation)
  //         t.same(response.json().incubating.from, initialEggs[0].username)
  //         t.same(response.json().incubating.to, initialEggs[0].username)
  //         t.ok(response.json().incubating.remainingDuration > 0)
  //         t.ok(
  //           response.json().incubating.remainingDuration <=
  //             INCUBATION_DURATION_MILLIS
  //         )
  //         t.ok(
  //           response.json().incubating.remainingCooldown >
  //             INCUBATION_DURATION_MILLIS
  //         )
  //         t.ok(
  //           response.json().incubating.remainingCooldown <=
  //             INCUBATION_DURATION_MILLIS + INCUBATION_COOLDOWN_MILLIS
  //         )

  //         t.end()

  //         resolve(true)
  //       }
  //     )
  //   })
  // })
})
