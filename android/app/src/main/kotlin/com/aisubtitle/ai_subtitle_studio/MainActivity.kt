package com.aisubtitle.ai_subtitle_studio

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aisubtitle.ai_sub_mini/storage"
    private val REQUEST_CODE_PICK_DIRECTORY = 9923
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToPublicDownloads" -> {
                    val fileName = call.argument<String>("fileName") ?: "subtitles.srt"
                    val content = call.argument<String>("content") ?: ""
                    val mimeType = call.argument<String>("mimeType") ?: "text/plain"

                    try {
                        val savedPath = saveToDownloads(fileName, content, mimeType)
                        result.success(savedPath)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }
                "pickDirectory" -> {
                    if (pendingResult != null) {
                        result.error("BUSY", "Directory picker is already active", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                        )
                    }
                    startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
                }
                "saveToCustomDirectory" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    val fileName = call.argument<String>("fileName") ?: "subtitles.srt"
                    val content = call.argument<String>("content") ?: ""
                    val mimeType = call.argument<String>("mimeType") ?: "text/plain"

                    if (treeUriStr == null) {
                        result.error("INVALID_URI", "Tree URI is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val treeUri = Uri.parse(treeUriStr)
                        val pickedDir = DocumentFile.fromTreeUri(applicationContext, treeUri)
                        if (pickedDir != null && pickedDir.canWrite()) {
                            val existing = pickedDir.findFile(fileName)
                            existing?.delete()

                            val docFile = pickedDir.createFile(mimeType, fileName)
                                ?: throw Exception("Failed to create document in selected folder")

                            contentResolver.openOutputStream(docFile.uri)?.use { os ->
                                os.write(content.toByteArray(Charsets.UTF_8))
                                os.flush()
                            }
                            result.success(docFile.uri.toString())
                        } else {
                            result.error("PERMISSION_DENIED", "Cannot write to selected directory", null)
                        }
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }
                "checkDirectoryAccess" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    if (treeUriStr == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val treeUri = Uri.parse(treeUriStr)
                        val doc = DocumentFile.fromTreeUri(applicationContext, treeUri)
                        result.success(doc != null && doc.canWrite())
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(fileName: String, content: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, "Download/AI Subtitles/")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = resolver.insert(collection, values)
                ?: throw Exception("Could not insert file into MediaStore Downloads")

            resolver.openOutputStream(uri)?.use { os ->
                os.write(content.toByteArray(Charsets.UTF_8))
                os.flush()
            }

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            return "/storage/emulated/0/Download/AI Subtitles/$fileName"
        } else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val aiSubDir = File(downloadsDir, "AI Subtitles")
            if (!aiSubDir.exists()) {
                aiSubDir.mkdirs()
            }
            val targetFile = File(aiSubDir, fileName)
            FileOutputStream(targetFile).use { fos ->
                fos.write(content.toByteArray(Charsets.UTF_8))
                fos.flush()
            }
            return targetFile.absolutePath
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_DIRECTORY) {
            val res = pendingResult
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && data != null && data.data != null) {
                val uri = data.data!!
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (e: Exception) {
                    // Ignore if already persisted
                }

                val doc = DocumentFile.fromTreeUri(applicationContext, uri)
                val displayName = doc?.name ?: DocumentsContract.getTreeDocumentId(uri)

                val response = mapOf(
                    "uri" to uri.toString(),
                    "displayName" to displayName
                )
                res?.success(response)
            } else {
                res?.success(null)
            }
        }
    }
}
