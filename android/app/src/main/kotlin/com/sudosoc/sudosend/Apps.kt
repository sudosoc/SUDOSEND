package com.sudosoc.sudosend

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import kotlin.concurrent.thread

/**
 * App sharing: list installed apps with their APK files (base + splits),
 * describe a received APK (name, package, version, signer) and install one
 * or several APKs (split apps) through PackageInstaller.
 */
object Apps {
    private val main = Handler(Looper.getMainLooper())

    private fun pm(ctx: Context): PackageManager = ctx.packageManager

    @Suppress("DEPRECATION")
    private fun packageInfo(pm: PackageManager, pkg: String, flags: Int): PackageInfo =
        if (Build.VERSION.SDK_INT >= 33) pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(flags.toLong()))
        else pm.getPackageInfo(pkg, flags)

    private fun icon(d: Drawable, size: Int = 96): ByteArray {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    /** Apps that show up in the launcher (no QUERY_ALL_PACKAGES needed). */
    fun list(ctx: Context, result: MethodChannel.Result) {
        thread(name = "sudosend-apps") {
            try {
                val pm = pm(ctx)
                val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                @Suppress("DEPRECATION")
                val infos = if (Build.VERSION.SDK_INT >= 33) {
                    pm.queryIntentActivities(launcher, PackageManager.ResolveInfoFlags.of(0))
                } else {
                    pm.queryIntentActivities(launcher, 0)
                }
                val seen = HashSet<String>()
                val out = ArrayList<Map<String, Any?>>()
                for (ri in infos) {
                    val pkg = ri.activityInfo?.packageName ?: continue
                    if (!seen.add(pkg)) continue
                    try {
                        val pi = packageInfo(pm, pkg, 0)
                        val ai = pi.applicationInfo ?: continue
                        val paths = ArrayList<String>()
                        paths.add(ai.sourceDir)
                        ai.splitSourceDirs?.let { paths.addAll(it) }
                        if (paths.any { !File(it).canRead() }) continue
                        val system = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                            (ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
                        out.add(
                            mapOf(
                                "label" to pm.getApplicationLabel(ai).toString(),
                                "package" to pkg,
                                "version" to (pi.versionName ?: ""),
                                "versionCode" to code,
                                "paths" to paths,
                                "size" to paths.sumOf { File(it).length() },
                                "system" to system,
                                "updated" to pi.lastUpdateTime,
                                "icon" to icon(pm.getApplicationIcon(ai)),
                            )
                        )
                    } catch (_: Exception) {
                    }
                }
                out.sortBy { (it["label"] as String).lowercase() }
                main.post { result.success(out) }
            } catch (e: Exception) {
                main.post { result.error("apps", e.message, null) }
            }
        }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    @Suppress("DEPRECATION")
    private fun signers(pi: PackageInfo): List<String> =
        if (Build.VERSION.SDK_INT >= 28) {
            val s = pi.signingInfo ?: return emptyList()
            val certs = if (s.hasMultipleSigners()) s.apkContentsSigners else s.signingCertificateHistory
            certs?.map { sha256(it.toByteArray()) } ?: emptyList()
        } else {
            pi.signatures?.map { sha256(it.toByteArray()) } ?: emptyList()
        }

    /** What a received APK is, and how it relates to what is installed. */
    fun apkInfo(ctx: Context, path: String, result: MethodChannel.Result) {
        thread(name = "sudosend-apkinfo") {
            try {
                val pm = pm(ctx)
                @Suppress("DEPRECATION")
                val signFlag = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                val flags = PackageManager.GET_PERMISSIONS or signFlag
                @Suppress("DEPRECATION")
                val pi = (if (Build.VERSION.SDK_INT >= 33) {
                    pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(flags.toLong()))
                } else {
                    pm.getPackageArchiveInfo(path, flags)
                }) ?: run {
                    main.post { result.success(null) }
                    return@thread
                }
                val ai = pi.applicationInfo
                ai?.sourceDir = path
                ai?.publicSourceDir = path
                @Suppress("DEPRECATION")
                val code = if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
                val signer = signers(pi)
                var installedVersion: String? = null
                var installedCode: Long? = null
                var sameSigner: Boolean? = null
                try {
                    @Suppress("DEPRECATION")
                    val sigFlag = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                    val installed = packageInfo(pm, pi.packageName, sigFlag)
                    installedVersion = installed.versionName
                    @Suppress("DEPRECATION")
                    installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                    val have = signers(installed)
                    sameSigner = signer.isNotEmpty() && have.isNotEmpty() && signer.any { it in have }
                } catch (_: PackageManager.NameNotFoundException) {
                }
                val info = mapOf(
                    "label" to (ai?.let { pm.getApplicationLabel(it).toString() } ?: pi.packageName),
                    "package" to pi.packageName,
                    "version" to (pi.versionName ?: ""),
                    "versionCode" to code,
                    "minSdk" to (if (Build.VERSION.SDK_INT >= 24) ai?.minSdkVersion else null),
                    "targetSdk" to ai?.targetSdkVersion,
                    "permissions" to (pi.requestedPermissions?.toList() ?: emptyList<String>()),
                    "signer" to signer.firstOrNull(),
                    "installedVersion" to installedVersion,
                    "installedCode" to installedCode,
                    "sameSigner" to sameSigner,
                    "icon" to (ai?.let { icon(pm.getApplicationIcon(it)) }),
                )
                main.post { result.success(info) }
            } catch (e: Exception) {
                main.post { result.error("apk", e.message, null) }
            }
        }
    }

    /** Installs one APK or a split set; Android asks the user to confirm. */
    fun install(ctx: Context, paths: List<String>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !ctx.packageManager.canRequestPackageInstalls()) {
            try {
                ctx.startActivity(
                    Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        android.net.Uri.parse("package:${ctx.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Exception) {
            }
            result.success("permission")
            return
        }
        thread(name = "sudosend-install") {
            try {
                val installer = ctx.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                val id = installer.createSession(params)
                installer.openSession(id).use { session ->
                    for (p in paths) {
                        val f = File(p)
                        f.inputStream().use { input ->
                            session.openWrite(f.name, 0, f.length()).use { out ->
                                input.copyTo(out)
                                session.fsync(out)
                            }
                        }
                    }
                    var flags = PendingIntent.FLAG_UPDATE_CURRENT
                    if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
                    val pending = PendingIntent.getBroadcast(ctx, id, Intent(ctx, InstallReceiver::class.java), flags)
                    session.commit(pending.intentSender)
                }
                main.post { result.success("ok") }
            } catch (e: Exception) {
                main.post { result.success("error: ${e.message}") }
            }
        }
    }
}

/** Receives PackageInstaller results: shows the confirm screen, reports the outcome. */
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    if (confirm != null) context.startActivity(confirm)
                } catch (_: Exception) {
                }
            }
            else -> Bridge.emit(
                "onInstallResult",
                mapOf(
                    "ok" to (status == PackageInstaller.STATUS_SUCCESS),
                    "status" to status,
                    "message" to intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
                    "package" to intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME),
                ),
            )
        }
    }
}
