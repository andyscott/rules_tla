load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def github_repository(**kwargs):
    name = kwargs["name"]
    ref = kwargs["ref"]
    archive_sha = kwargs["archive_sha"]

    [repo_owner, repo_name] = kwargs["repo"].split("/")

    http_archive(
        name = name,
        strip_prefix = "%s-%s" % (repo_name, ref),
        sha256 = archive_sha,
        url = "https://github.com/%s/%s/archive/%s.zip" % (repo_owner, repo_name, ref),
    )
