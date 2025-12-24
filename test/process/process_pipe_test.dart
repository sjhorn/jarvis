import 'package:jarvis/src/process/process_pipe.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessPipe', () {
    group('start', () {
      test('should start a simple process successfully', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);

        // Act
        await pipe.start();

        // Assert
        expect(pipe.isRunning, isTrue);

        // Cleanup
        await pipe.stop();
      });

      test(
        'should throw ProcessPipeException when executable not found',
        () async {
          // Arrange
          final pipe = ProcessPipe(
            executable: 'nonexistent_command_12345',
            arguments: [],
          );

          // Act & Assert
          expect(() => pipe.start(), throwsA(isA<ProcessPipeException>()));
        },
      );

      test(
        'should throw when start is called on already running process',
        () async {
          // Arrange
          final pipe = ProcessPipe(executable: 'cat', arguments: []);
          await pipe.start();

          // Act & Assert
          expect(() => pipe.start(), throwsA(isA<ProcessPipeException>()));

          // Cleanup
          await pipe.stop();
        },
      );
    });

    group('send', () {
      test('should send input and receive output', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);
        await pipe.start();

        // Act
        final response = await pipe.send('hello\n');

        // Assert
        expect(response.trim(), equals('hello'));

        // Cleanup
        await pipe.stop();
      });

      test('should handle multiple sequential sends', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);
        await pipe.start();

        // Act & Assert
        final response1 = await pipe.send('first\n');
        expect(response1.trim(), equals('first'));

        final response2 = await pipe.send('second\n');
        expect(response2.trim(), equals('second'));

        // Cleanup
        await pipe.stop();
      });

      test('should throw when send is called on non-running process', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);

        // Act & Assert
        expect(() => pipe.send('hello'), throwsA(isA<ProcessPipeException>()));
      });

      test('should throw ProcessPipeException on timeout', () async {
        // Arrange
        final pipe = ProcessPipe(
          executable: 'cat',
          arguments: [],
          responseTimeout: const Duration(milliseconds: 100),
        );
        await pipe.start();

        // Act & Assert - cat waits for newline, so sending without \n should timeout
        expect(
          () => pipe.send('hello', waitForResponse: true),
          throwsA(
            isA<ProcessPipeException>().having(
              (e) => e.message,
              'message',
              contains('timeout'),
            ),
          ),
        );

        // Cleanup
        await pipe.stop();
      });
    });

    group('stop', () {
      test('should stop a running process', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);
        await pipe.start();
        expect(pipe.isRunning, isTrue);

        // Act
        await pipe.stop();

        // Assert
        expect(pipe.isRunning, isFalse);
      });

      test('should be safe to call stop on non-running process', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);

        // Act & Assert - should not throw
        await pipe.stop();
        expect(pipe.isRunning, isFalse);
      });

      test('should properly clean up resources on stop', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);
        await pipe.start();

        // Act
        await pipe.stop();

        // Assert - subsequent operations should fail appropriately
        expect(() => pipe.send('hello'), throwsA(isA<ProcessPipeException>()));
      });
    });

    group('restart', () {
      test('should restart a stopped process', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);
        await pipe.start();
        await pipe.stop();
        expect(pipe.isRunning, isFalse);

        // Act
        await pipe.restart();

        // Assert
        expect(pipe.isRunning, isTrue);

        // Cleanup
        await pipe.stop();
      });

      test('should restart a running process', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);
        await pipe.start();

        // Act
        await pipe.restart();

        // Assert
        expect(pipe.isRunning, isTrue);
        final response = await pipe.send('test\n');
        expect(response.trim(), equals('test'));

        // Cleanup
        await pipe.stop();
      });
    });

    group('outputStream', () {
      test('should emit output from process', () async {
        // Arrange
        final pipe = ProcessPipe(executable: 'cat', arguments: []);
        await pipe.start();
        final outputs = <String>[];
        final subscription = pipe.outputStream.listen(outputs.add);

        // Act
        pipe.sendRaw('hello\n');
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(outputs.join().trim(), equals('hello'));

        // Cleanup
        await subscription.cancel();
        await pipe.stop();
      });
    });

    group('process termination detection', () {
      test('should detect when process exits', () async {
        // Arrange
        // Use 'echo' which exits immediately after output
        final pipe = ProcessPipe(executable: 'echo', arguments: ['hello']);
        await pipe.start();

        // Act - wait for process to exit naturally
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Assert
        expect(pipe.isRunning, isFalse);
      });

      test('should provide exit code when process terminates', () async {
        // Arrange
        final pipe = ProcessPipe(
          executable: 'sh',
          arguments: ['-c', 'exit 42'],
        );
        await pipe.start();

        // Act
        final exitCode = await pipe.exitCode;

        // Assert
        expect(exitCode, equals(42));
        expect(pipe.isRunning, isFalse);
      });
    });

    group('error handling', () {
      test('should capture stderr output', () async {
        // Arrange
        final pipe = ProcessPipe(
          executable: 'sh',
          arguments: ['-c', 'echo error >&2'],
        );
        await pipe.start();
        final errors = <String>[];
        final subscription = pipe.errorStream.listen(errors.add);

        // Act
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Assert
        expect(errors.join().trim(), equals('error'));

        // Cleanup
        await subscription.cancel();
        await pipe.stop();
      });
    });
  });
}
