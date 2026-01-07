package kr.co.weeds.kafkademo;

import lombok.RequiredArgsConstructor;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
public class TestLogController {

    private final KafkaTemplate<String, String> kafkaTemplate;

    // 호출 주소: POST http://localhost:8081/api/test/produce?message=테스트로그
    @PostMapping("/api/test/produce")
    public String produceLog(@RequestParam String message) {
        kafkaTemplate.send("topic-a", message); 
        return "Sent to topic-a: " + message;
    }
}