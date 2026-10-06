package dev.tempo.tempo

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// FlutterFragmentActivity: Health Connect asks for permissions through
// registerForActivityResult, which needs a ComponentActivity.
class MainActivity : FlutterFragmentActivity() {
    private var pendingPick: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val pickTree =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val result = pendingPick ?: return@registerForActivityResult
            pendingPick = null
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                result.success(mapOf("token" to uri.toString(), "name" to treeName(uri)))
            } catch (e: Exception) {
                result.error("permission", e.message, null)
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // `tempo/backup_folder` (lib/src/core/backup.dart): a folder picked
        // through the Storage Access Framework, kept as a persisted tree
        // URI. TODO(verify) on device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tempo/backup_folder")
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pick") {
            if (pendingPick != null) {
                result.error("busy", "Picker already open", null)
                return
            }
            pendingPick = result
            pickTree.launch(null)
            return
        }
        if (call.method !in setOf("list", "read", "write", "delete")) {
            result.notImplemented()
            return
        }
        val token = call.argument<String>("token")
        if (token == null) {
            result.error("bad_token", "No folder token", null)
            return
        }
        val tree = Uri.parse(token)
        io.execute {
            try {
                val value: Any? = when (call.method) {
                    "list" -> list(tree)
                    "read" -> read(tree, name(call))
                    "write" -> {
                        write(tree, name(call), call.argument<ByteArray>("bytes") ?: ByteArray(0))
                        null
                    }
                    else -> {
                        find(tree, name(call))?.let {
                            DocumentsContract.deleteDocument(contentResolver, it)
                        }
                        null
                    }
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("io", e.message, null) }
            }
        }
    }

    private fun name(call: MethodCall): String {
        val n = call.argument<String>("name")
        require(!n.isNullOrEmpty() && !n.contains('/')) { "Bad name" }
        return n
    }

    private fun parentDoc(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )

    private fun treeName(tree: Uri): String =
        contentResolver.query(
            parentDoc(tree),
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: "Backup folder"

    /// (document id, name, size, last modified) of each file in the folder.
    private fun children(tree: Uri): List<Map<String, Any?>> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val cols = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(uri, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getString(0),
                        "name" to c.getString(1),
                        "size" to if (c.isNull(2)) null else c.getLong(2),
                        "modified" to if (c.isNull(3)) null else c.getLong(3),
                    ),
                )
            }
        }
        return out
    }

    private fun list(tree: Uri): List<Map<String, Any?>> =
        children(tree).map { it - "id" }

    private fun find(tree: Uri, name: String): Uri? =
        children(tree).firstOrNull { it["name"] == name }?.let {
            DocumentsContract.buildDocumentUriUsingTree(tree, it["id"] as String)
        }

    private fun read(tree: Uri, name: String): ByteArray {
        val doc = find(tree, name) ?: throw IllegalStateException("$name not found")
        return contentResolver.openInputStream(doc)?.use { it.readBytes() }
            ?: throw IllegalStateException("Can't open $name")
    }

    private fun write(tree: Uri, name: String, bytes: ByteArray) {
        find(tree, name)?.let { DocumentsContract.deleteDocument(contentResolver, it) }
        val doc = DocumentsContract.createDocument(
            contentResolver,
            parentDoc(tree),
            "application/octet-stream",
            name,
        ) ?: throw IllegalStateException("Can't create $name")
        contentResolver.openOutputStream(doc, "w")?.use { it.write(bytes) }
            ?: throw IllegalStateException("Can't write $name")
    }
}
