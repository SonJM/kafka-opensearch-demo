package kr.co.weeds.kafkademo.domain;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

public record LogDocument(
    String message,
    String timestamp,
    Map<String, Object> extraData
) {
    public static LogDocument from(String message) {
        return new LogDocument(message, Instant.now().toString(), new HashMap<>());
    }

    public Map<String, Object> toMap() {
        Map<String, Object> map = new HashMap<>();
        map.put("message", message);
        map.put("timestamp", timestamp);
        if (extraData != null) {
            map.putAll(extraData);
        }
        return map;
    }
}
