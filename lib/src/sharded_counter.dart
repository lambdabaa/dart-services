// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library is basic implementation of a sharded counter
library services.counter;

import 'dart:async';
import 'dart:math' as math;

import 'package:gcloud/db.dart' as db;

final SHARDS_COUNT = 20;

class Counter {
  static Future increment(String name, {int increment = 1}) {
    db.DatastoreDB datastore = db.dbService;
    int shardId = math.Random().nextInt(SHARDS_COUNT);
    return _getCounterShard(name, shardId, datastore).then((counter) {
      counter.count++;
      return datastore.withTransaction((transaction) {
        return transaction.lookup([counter.key]).then((List<db.Model> models) {
          _ShardedCounter model = models[0];
          model.count += increment;

          transaction.queueMutations(inserts: [model]);
          return transaction.commit();
        });
      });
    });
  }

  static Future<int> getTotal(String name) {
    int total = 0;
    var query = db.dbService.query<_ShardedCounter>()
      ..filter("counterName =", name);

    return query.run().toList().then((List<db.Model> models) {
      models.forEach((db.Model m) => total += (m as _ShardedCounter).count);
      return total;
    });
  }

  static Future<_ShardedCounter> _getCounterShard(
      String name, int shardId, db.DatastoreDB datastore) {
    var query = datastore.query<_ShardedCounter>()
      ..filter("counterName =", name)
      ..filter("shardId =", shardId);
    Future<List<db.Model>> results = query.run().toList();

    // Test whether we have been given an id.
    return results.then((List<db.Model> models) {
      if (models.length == 0) {
        _ShardedCounter newCounter = _ShardedCounter()
          ..counterName = name
          ..count = 0
          ..shardId = shardId;

        return datastore.commit(inserts: [newCounter]).then((result) {
          return newCounter;
        });
      } else {
        return Future.value(models[0] as _ShardedCounter);
      }
    });
  }
}

@db.Kind()
class _ShardedCounter extends db.Model {
  @db.StringProperty()
  String counterName;

  @db.IntProperty()
  int count;

  @db.IntProperty()
  int shardId;
}
