package kr.co.weeds.kafkademo;

import kr.co.weeds.kafkademo.domain.LogDocument;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.opensearch.action.get.GetRequest;
import org.opensearch.action.get.GetResponse;
import org.opensearch.action.index.IndexRequest;
import org.opensearch.action.index.IndexResponse;
import org.opensearch.client.RequestOptions;
import org.opensearch.client.RestHighLevelClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.Map;

@Service
@Slf4j
@RequiredArgsConstructor
public class LogWorkerService {
	
	private final KafkaTemplate<String, String> kafkaTemplate;
	private final RestHighLevelClient openSearchClient;
	
	// 각 서비스별 전용 인덱스 정의
	private static final String INDEX_W1 = "w1-logs";
	private static final String INDEX_W2 = "w2-logs";
	private static final String INDEX_W3 = "w3-logs";
	
	@Value("${app.role}")
	private String role;
	
	@Value("${output.topic.1:#{null}}")
	private String outputTopic1;
	
	@Value("${output.topic.2:#{null}}")
	private String outputTopic2;
	
	/**
	 * 공통 컨슈머 로직
	 * Docker Compose에서 설정한 INPUT_TOPIC을 구독합니다.
	 */
	@KafkaListener(topics = "${input.topic}", groupId = "group-${app.role}")
	public void consume(ConsumerRecord<String, String> record) {
		log.info(">>> [Role: {}] Consumed from Partition: {}, Offset: {}", role, record.partition(), record.offset());
		
		try {
			switch (role) {
				case "W1" -> processW1(record.value());
				case "W2" -> processW2(record.value());
				case "W3" -> processW3(record.value());
				default -> log.warn("Unknown Role: {}", role);
			}
		} catch (IOException e) {
			log.error("OpenSearch IO Error processing message: {}", record.value(), e);
		} catch (Exception e) {
			log.error("Unexpected error: ", e);
		}
	}
	
	// --- [W1] Ingestion: Index to 'w1-logs' ---
	private void processW1(String message) throws IOException, InterruptedException {
		Thread.sleep(100);
		LogDocument doc = LogDocument.from(message);
		IndexRequest request = new IndexRequest(INDEX_W1)
				.source(doc.toMap());

		IndexResponse response = openSearchClient.index(request, RequestOptions.DEFAULT);
		String docId = response.getId();
		
		log.info("[W1] Indexed to '{}'. DocID: {}", INDEX_W1, docId);
		
		if (outputTopic1 != null && !outputTopic1.isEmpty()) {
			kafkaTemplate.send(outputTopic1, docId);
			log.info("[W1] Sent DocID to {}", outputTopic1);
		}
		if (outputTopic2 != null && !outputTopic2.isEmpty()) {
			kafkaTemplate.send(outputTopic2, docId);
			log.info("[W1] Sent DocID to {}", outputTopic2);
		}
	}
	
	// --- [W2] Analysis: Get from 'w1-logs' -> Index to 'w2-logs' ---
	private void processW2(String docId) throws IOException, InterruptedException {
		Thread.sleep(100);
		GetRequest getRequest = new GetRequest(INDEX_W1, docId);
		GetResponse getResponse = openSearchClient.get(getRequest, RequestOptions.DEFAULT);
		
		if (getResponse.isExists()) {
			Map<String, Object> source = getResponse.getSourceAsMap();
			log.info("[W2] Retrieved doc from '{}'. Re-indexing to '{}'...", INDEX_W1, INDEX_W2);
			
			IndexRequest indexRequest = new IndexRequest(INDEX_W2)
					.id(docId)
					.source(source);
			
			openSearchClient.index(indexRequest, RequestOptions.DEFAULT);
			log.info("[W2] Re-indexing complete. DocID: {}", docId);
		} else {
			log.warn("[W2] Original document not found in '{}' for ID: {}", INDEX_W1, docId);
		}
	}
	
	// --- [W3] Final Indexing: Get from 'w1-logs' -> Index to 'w3-logs' ---
	private void processW3(String docId) throws IOException, InterruptedException {
		Thread.sleep(100);
		GetRequest getRequest = new GetRequest(INDEX_W1, docId);
		GetResponse getResponse = openSearchClient.get(getRequest, RequestOptions.DEFAULT);
		
		if (getResponse.isExists()) {
			Map<String, Object> source = getResponse.getSourceAsMap();
			log.info("[W3] Retrieved doc from '{}'. Re-indexing to '{}'...", INDEX_W1, INDEX_W3);
			
			IndexRequest indexRequest = new IndexRequest(INDEX_W3)
					.id(docId)
					.source(source);

			openSearchClient.index(indexRequest, RequestOptions.DEFAULT);
			log.info("[W3] Re-indexing complete. DocID: {}", docId);
		} else {
			log.warn("[W3] Original document not found in '{}' for ID: {}", INDEX_W1, docId);
		}
	}
}